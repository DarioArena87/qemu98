/*
 * QEMU Block driver for CUE/BIN CD-ROM images
 *
 * Parses a .cue sheet file, locates the referenced .bin file, and
 * exposes the data track as a read-only block device with 2048-byte
 * sectors (extracted from the raw 2352-byte CD sectors).
 *
 * Copyright (c) 2024 Win9x-QEMU98 Project
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "qemu/osdep.h"
#include "qapi/error.h"
#include "block/block-io.h"
#include "block/block_int.h"
#include "block/qdict.h"
#include "qemu/module.h"
#include "qobject/qdict.h"

/* CD sector sizes */
#define CUE_DATA_SECTOR_SIZE    2048
#define CUE_RAW_SECTOR_SIZE     2352

/*
 * Possible data offsets within a raw sector:
 *   MODE1/2048: sectors are already 2048 bytes, no offset needed
 *   MODE1/2352: 12 sync + 4 header + 2048 data + 288 ECC  → data at 16
 *   MODE2/2352: 12 sync + 4 header + 8 subheader + 2048 data + 280 ECC/EDC
 *               → data at 24
 */
#define CUE_MODE1_2048_OFFSET    0
#define CUE_MODE1_DATA_OFFSET   16
#define CUE_MODE2_DATA_OFFSET   24

typedef struct BDRVCueState {
    char* bin_path; /* resolved path to the .bin file */
    int raw_sector_size; /* 2352 or 2048 */
    int data_offset; /* byte offset within raw sector (0, 16, or 24) */
    int64_t data_start; /* byte offset in BIN where data starts (INDEX 00) */
    int64_t pregap_bytes; /* pregap between INDEX 00 and INDEX 01, in bytes */
    int64_t data_sectors; /* number of 2048-byte data sectors */
} BDRVCueState;

/*
 * Parse an MM:SS:FF timestamp into a frame count.
 * 1 frame = 1 CD sector (2352 raw bytes) = 1/75 second.
 */
static int cue_parse_timestamp(const char* str, int64_t* frames) {
    unsigned int mm, ss, ff;
    char dummy;

    if (sscanf(str, "%02u:%02u:%02u%c", &mm, &ss, &ff, &dummy) != 3) {
        return -EINVAL;
    }
    if (ss >= 60 || ff >= 75) {
        return -EINVAL;
    }
    *frames = ((int64_t) mm * 60 + ss) * 75 + ff;
    return 0;
}

/*
 * Parse a CUE sheet. We extract:
 *  - the first BIN file path from a FILE ... BINARY directive
 *  - the first data track's mode and INDEX 00/01 positions
 *
 * The virtual image starts at INDEX 00 (pregap start) if present,
 * otherwise at INDEX 01. The gap (pregap) is tracked in pregap_bytes.
 */
static int cue_parse(const char* cue_text, BDRVCueState* s, Error** errp) {
    const char* p = cue_text;
    const char* line_start;
    bool found_file = false;
    int current_track_mode = -1;
    int first_data_track_no = -1;
    int first_data_track_mode = -1;
    int64_t first_data_index00 = -1; /* -1 = no INDEX 00 found */
    int64_t first_data_index01 = 0;
    bool have_index01 = false;
    int track_number = 0;

    while (*p) {
        /* Skip whitespace / blank lines */
        while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') {
            p++;
        }
        if (*p == '\0') {
            break;
        }

        line_start = p;
        while (*p && *p != '\n' && *p != '\r') {
            p++;
        }

        if (g_ascii_strncasecmp(line_start, "FILE", 4) == 0) {
            const char* q = line_start + 4;
            const char* start_quote,* end_quote;

            while (*q == ' ' || *q == '\t') {
                q++;
            }
            if (*q != '"') {
                goto next_line;
            }
            start_quote = q + 1;
            end_quote = strchr(start_quote, '"');
            if (!end_quote) {
                goto next_line;
            }

            /* Only track the first FILE entry — multi-file CUEs are unsupported */
            if (!found_file) {
                s->bin_path = g_strndup(start_quote, end_quote - start_quote);

                /* Verify the BINARY keyword follows */
                q = end_quote + 1;
                while (*q == ' ' || *q == '\t') {
                    q++;
                }
                if (g_ascii_strncasecmp(q, "BINARY", 6) != 0) {
                    g_free(s->bin_path);
                    s->bin_path = NULL;
                    goto next_line;
                }
                found_file = true;
            }
        }
        else if (g_ascii_strncasecmp(line_start, "TRACK", 5) == 0) {
            const char* q = line_start + 5;
            char mode_str[32] = {0};

            while (*q == ' ' || *q == '\t') {
                q++;
            }
            track_number = atoi(q);
            while (*q >= '0' && *q <= '9') {
                q++;
            }
            while (*q == ' ' || *q == '\t') {
                q++;
            }
            sscanf(q, "%31s", mode_str);

            if (g_ascii_strcasecmp(mode_str, "MODE1/2352") == 0) {
                current_track_mode = CUE_MODE1_DATA_OFFSET;
            }
            else if (g_ascii_strcasecmp(mode_str, "MODE1/2048") == 0) {
                current_track_mode = CUE_MODE1_2048_OFFSET;
            }
            else if (g_ascii_strcasecmp(mode_str, "MODE2/2352") == 0) {
                current_track_mode = CUE_MODE2_DATA_OFFSET;
            }
            else {
                /* AUDIO or unknown — skip */
                current_track_mode = -1;
            }

            if (current_track_mode >= 0 && first_data_track_no < 0) {
                first_data_track_no = track_number;
                first_data_track_mode = current_track_mode;
            }
        }
        else if (g_ascii_strncasecmp(line_start, "INDEX", 5) == 0) {
            const char* q = line_start + 5;
            int index_num;
            char timestamp[16];
            int64_t frames;

            while (*q == ' ' || *q == '\t') {
                q++;
            }
            index_num = atoi(q);
            while (*q >= '0' && *q <= '9') {
                q++;
            }
            while (*q == ' ' || *q == '\t') {
                q++;
            }
            sscanf(q, "%15s", timestamp);

            if (cue_parse_timestamp(timestamp, &frames) < 0) {
                error_setg(errp, "Invalid INDEX timestamp in CUE file: '%s'", timestamp);
                return -EINVAL;
            }

            if (track_number == first_data_track_no) {
                if (index_num == 0) {
                    first_data_index00 = frames;
                }
                else if (index_num == 1) {
                    first_data_index01 = frames;
                    have_index01 = true;
                }
            }
        }

    next_line:
        if (*p) {
            p++;
        }
    }

    if (!found_file || !s->bin_path) {
        error_setg(errp, "CUE file contains no FILE ... BINARY entry");
        return -EINVAL;
    }

    if (first_data_track_no < 0 || !have_index01) {
        error_setg(errp, "CUE file contains no data track with INDEX 01");
        return -ENOTSUP;
    }

    s->data_offset = first_data_track_mode; /* 0, 16, or 24 */
    s->raw_sector_size = (s->data_offset == 0) ? CUE_DATA_SECTOR_SIZE : CUE_RAW_SECTOR_SIZE;

    /*
     * Data starts at INDEX 00 (if present) so the pregap is included.
     * If no INDEX 00 was specified, it defaults to INDEX 01 (no pregap).
     */
    if (first_data_index00 < 0) {
        first_data_index00 = first_data_index01;
    }

    if (first_data_index00 > first_data_index01) {
        error_setg(errp, "INDEX 00 is after INDEX 01 in data track");
        return -EINVAL;
    }

    s->data_start = first_data_index00 * s->raw_sector_size;

    /* Size of the pregap in raw bytes; reserved for future info exposure */
    s->pregap_bytes = (first_data_index01 - first_data_index00) * s->raw_sector_size;

    return 0;
}

static int cue_probe(const uint8_t* buf, int buf_size, const char* filename) {
    int len;

    if (!filename) {
        return 0;
    }

    len = strlen(filename);
    if (len > 4 && !g_ascii_strcasecmp(filename + len - 4, ".cue")) {
        return 2;
    }
    return 0;
}

static int cue_open(BlockDriverState* bs, QDict* options, int flags, Error** errp) {
    BDRVCueState* s = bs->opaque;
    g_autofree char* cue_text = NULL;
    g_autofree char* cue_dir = NULL;
    g_autoptr(GError) gerr = NULL;
    int64_t bin_size;
    int ret;

    GLOBAL_STATE_CODE();

    /* CUE/BIN images are always read-only */
    bdrv_graph_rdlock_main_loop();
    ret = bdrv_apply_auto_read_only(bs, NULL, errp);
    bdrv_graph_rdunlock_main_loop();
    if (ret < 0) {
        return ret;
    }

    /* The .cue filename is already in bs->filename (set by bdrv_open_common) */
    if (bs->filename[0] == '\0') {
        error_setg(errp, "No CUE filename specified");
        return -EINVAL;
    }

    /* Read the .cue file — they're always tiny text files */
    if (!g_file_get_contents(bs->filename, &cue_text, NULL, &gerr)) {
        error_setg(errp, "Could not read CUE file '%s': %s", bs->filename, gerr->message);
        return -EIO;
    }

    /* Determine the directory containing the .cue file for relative paths */
    cue_dir = g_path_get_dirname(bs->filename);

    /* Parse the CUE sheet */
    ret = cue_parse(cue_text, s, errp);
    if (ret < 0) {
        return ret;
    }

    /*
     * Resolve the BIN file path. If it's relative, resolve against
     * the .cue file's directory.
     */
    if (!g_path_is_absolute(s->bin_path)) {
        g_autofree char* resolved = g_build_filename(cue_dir, s->bin_path, NULL);
        g_free(s->bin_path);
        s->bin_path = g_steal_pointer(&resolved);
    }

    /*
     * The block layer passes a "file" option in the QDict pointing to the
     * protocol child (the .cue file). Since we read the .cue via
     * g_file_get_contents() and open the .bin ourselves, we must consume
     * these options to prevent "does not support the option 'file'" errors.
     */
    {
        QDict* file_opts = NULL;
        qdict_extract_subqdict(options, &file_opts, "file.");
        qobject_unref(file_opts);
        qdict_del(options, "file");
    }

    /*
     * Open the BIN file as bs->file. We construct a QDict that tells
     * the block layer to open the BIN file with the raw format driver.
     * This child becomes our bs->file, through which all I/O passes.
     */
    {
        QDict* bin_options = qdict_new();
        qdict_put_str(bin_options, "driver", "raw");
        qdict_put_str(bin_options, "filename", s->bin_path);

        bs->file = bdrv_open_child(s->bin_path, bin_options, "file", bs, &child_of_bds, BDRV_CHILD_DATA | BDRV_CHILD_PRIMARY, false, errp);
        if (!bs->file) {
            return -EINVAL;
        }
    }

    GRAPH_RDLOCK_GUARD_MAINLOOP();

    /* Calculate total data sectors from the BIN file size */
    bin_size = bdrv_getlength(bs->file->bs);
    if (bin_size < 0) {
        error_setg_errno(errp, -bin_size, "Could not determine BIN file size");
        return bin_size;
    }

    if (bin_size < s->data_start) {
        error_setg(errp, "BIN file (%" PRId64 " bytes) is smaller than " "data start offset (%" PRId64 " bytes)", bin_size, s->data_start);
        return -EINVAL;
    }

    /* Remaining bytes after the data start, in raw sectors */
    s->data_sectors = (bin_size - s->data_start) / s->raw_sector_size;

    /* total_sectors is always in 512-byte (BDRV_SECTOR_SIZE) units */
    bs->total_sectors = s->data_sectors * (CUE_DATA_SECTOR_SIZE / BDRV_SECTOR_SIZE);

    return 0;
}

static void cue_close(BlockDriverState* bs) {
    BDRVCueState* s = bs->opaque;
    g_free(s->bin_path);
    s->bin_path = NULL;
}

static void cue_refresh_limits(BlockDriverState* bs, Error** errp) {
    bs->bl.request_alignment = CUE_DATA_SECTOR_SIZE;
}

static int coroutine_fn GRAPH_RDLOCK cue_co_preadv(BlockDriverState* bs, int64_t offset, int64_t bytes, QEMUIOVector* qiov, BdrvRequestFlags flags) {
    BDRVCueState* s = bs->opaque;
    int64_t sector_num = offset / CUE_DATA_SECTOR_SIZE;
    int64_t sector_off = offset % CUE_DATA_SECTOR_SIZE;
    uint64_t bytes_done = 0;
    QEMUIOVector local_qiov;
    int ret;

    assert(QEMU_IS_ALIGNED(offset, CUE_DATA_SECTOR_SIZE));
    assert(QEMU_IS_ALIGNED(bytes, CUE_DATA_SECTOR_SIZE));

    qemu_iovec_init(&local_qiov, qiov->niov);

    while (bytes_done < bytes) {
        int64_t chunk = MIN(bytes - bytes_done, CUE_DATA_SECTOR_SIZE - sector_off);
        int64_t raw_offset;

        raw_offset = s->data_start + sector_num * s->raw_sector_size + s->data_offset + sector_off;

        qemu_iovec_reset(&local_qiov);
        qemu_iovec_concat(&local_qiov, qiov, bytes_done, chunk);

        ret = bdrv_co_preadv(bs->file, raw_offset, chunk, &local_qiov, 0);
        if (ret < 0) {
            goto fail;
        }

        bytes_done += chunk;
        sector_off = 0;
        sector_num++;
    }

    ret = 0;
fail:
    qemu_iovec_destroy(&local_qiov);
    return ret;
}

static int coroutine_fn GRAPH_RDLOCK cue_co_block_status(
    BlockDriverState* bs,
    unsigned int mode,
    int64_t offset,
    int64_t bytes,
    int64_t* pnum,
    int64_t* map,
    BlockDriverState** file
) {
    BDRVCueState* s = bs->opaque;
    int64_t sector_num = offset / CUE_DATA_SECTOR_SIZE;

    *pnum = bytes;
    *file = bs->file->bs;
    *map = s->data_start + sector_num * s->raw_sector_size + s->data_offset;
    return BDRV_BLOCK_RAW | BDRV_BLOCK_OFFSET_VALID | BDRV_BLOCK_DATA;
}

static int64_t coroutine_fn GRAPH_RDLOCK cue_co_getlength(BlockDriverState* bs) {
    BDRVCueState* s = bs->opaque;
    return s->data_sectors * CUE_DATA_SECTOR_SIZE;
}

static BlockDriver bdrv_cue = {
    .format_name = "cue",
    .instance_size = sizeof(BDRVCueState),
    .bdrv_probe = cue_probe,
    .bdrv_open = cue_open,
    .bdrv_close = cue_close,
    .bdrv_child_perm = bdrv_default_perms,
    .bdrv_refresh_limits = cue_refresh_limits,
    .bdrv_co_preadv = cue_co_preadv,
    .bdrv_co_block_status = cue_co_block_status,
    .bdrv_co_getlength = cue_co_getlength,
    .is_format = true,
};

static void bdrv_cue_init(void) {
    bdrv_register(&bdrv_cue);
}

block_init(bdrv_cue_init);
