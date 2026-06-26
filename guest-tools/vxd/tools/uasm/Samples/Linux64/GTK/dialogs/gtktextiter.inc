;--- include file created by h2incx v0.99.20 (copyright 2005-2009 japheth)

GtkTextSearchFlags typedef DWORD
GTK_TEXT_SEARCH_VISIBLE_ONLY = 1  shl  0 
GTK_TEXT_SEARCH_TEXT_ONLY = 1  shl  1 
GTK_TEXT_SEARCH_CASE_INSENSITIVE = 1  shl  2 ;\ Possible future plans \ 

GtkTextBuffer typedef _GtkTextBuffer

GTK_TYPE_TEXT_ITER	EQU	<( gtk_text_iter_get_type ( ) )>
_GtkTextIter	struct 
dummy1	gpointer	?
dummy2	gpointer	?
dummy3	gint	?
dummy4	gint	?
dummy5	gint	?
dummy6	gint	?
dummy7	gint	?
dummy8	gint	?
dummy9	gpointer	?
dummy10	gpointer	?
dummy11	gint	?
dummy12	gint	?
dummy13	gint	?
dummy14	gpointer	?
_GtkTextIter	ends

GtkTextIter TYPEDEF _GtkTextIter

gtk_text_iter_get_buffer proto  :ptr GtkTextIter
gtk_text_iter_copy proto  :ptr GtkTextIter
gtk_text_iter_free proto  :ptr GtkTextIter
gtk_text_iter_assign proto  :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_get_type proto ; :void
gtk_text_iter_get_offset proto  :ptr GtkTextIter
gtk_text_iter_get_line proto  :ptr GtkTextIter
gtk_text_iter_get_line_offset proto  :ptr GtkTextIter
gtk_text_iter_get_line_index proto  :ptr GtkTextIter
gtk_text_iter_get_visible_line_offset proto  :ptr GtkTextIter
gtk_text_iter_get_visible_line_index proto  :ptr GtkTextIter
gtk_text_iter_get_char proto  :ptr GtkTextIter
gtk_text_iter_get_slice proto  :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_get_text proto  :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_get_visible_slice proto  :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_get_visible_text proto  :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_get_pixbuf proto  :ptr GtkTextIter
gtk_text_iter_get_marks proto  :ptr GtkTextIter
gtk_text_iter_get_child_anchor proto  :ptr GtkTextIter
gtk_text_iter_get_toggled_tags proto  :ptr GtkTextIter, :gboolean
gtk_text_iter_begins_tag proto  :ptr GtkTextIter, :ptr GtkTextTag
gtk_text_iter_ends_tag proto  :ptr GtkTextIter, :ptr GtkTextTag
gtk_text_iter_toggles_tag proto  :ptr GtkTextIter, :ptr GtkTextTag
gtk_text_iter_has_tag proto  :ptr GtkTextIter, :ptr GtkTextTag
gtk_text_iter_get_tags proto  :ptr GtkTextIter
gtk_text_iter_editable proto  :ptr GtkTextIter, :gboolean
gtk_text_iter_can_insert proto  :ptr GtkTextIter, :gboolean
gtk_text_iter_starts_word proto  :ptr GtkTextIter
gtk_text_iter_ends_word proto  :ptr GtkTextIter
gtk_text_iter_inside_word proto  :ptr GtkTextIter
gtk_text_iter_starts_sentence proto  :ptr GtkTextIter
gtk_text_iter_ends_sentence proto  :ptr GtkTextIter
gtk_text_iter_inside_sentence proto  :ptr GtkTextIter
gtk_text_iter_starts_line proto  :ptr GtkTextIter
gtk_text_iter_ends_line proto  :ptr GtkTextIter
gtk_text_iter_is_cursor_position proto  :ptr GtkTextIter
gtk_text_iter_get_chars_in_line proto  :ptr GtkTextIter
gtk_text_iter_get_bytes_in_line proto  :ptr GtkTextIter
;gtk_text_iter_get_attributes proto  :ptr GtkTextIter, :ptr GtkTextAttributes ; !!! NB gtktextattributes.inc required !!!
gtk_text_iter_get_language proto  :ptr GtkTextIter
gtk_text_iter_is_end proto  :ptr GtkTextIter
gtk_text_iter_is_start proto  :ptr GtkTextIter
gtk_text_iter_forward_char proto  :ptr GtkTextIter
gtk_text_iter_backward_char proto  :ptr GtkTextIter
gtk_text_iter_forward_chars proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_chars proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_line proto  :ptr GtkTextIter
gtk_text_iter_backward_line proto  :ptr GtkTextIter
gtk_text_iter_forward_lines proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_lines proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_word_end proto  :ptr GtkTextIter
gtk_text_iter_backward_word_start proto  :ptr GtkTextIter
gtk_text_iter_forward_word_ends proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_word_starts proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_visible_line proto  :ptr GtkTextIter
gtk_text_iter_backward_visible_line proto  :ptr GtkTextIter
gtk_text_iter_forward_visible_lines proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_visible_lines proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_visible_word_end proto  :ptr GtkTextIter
gtk_text_iter_backward_visible_word_start proto  :ptr GtkTextIter
gtk_text_iter_forward_visible_word_ends proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_visible_word_starts proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_sentence_end proto  :ptr GtkTextIter
gtk_text_iter_backward_sentence_start proto  :ptr GtkTextIter
gtk_text_iter_forward_sentence_ends proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_sentence_starts proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_cursor_position proto  :ptr GtkTextIter
gtk_text_iter_backward_cursor_position proto  :ptr GtkTextIter
gtk_text_iter_forward_cursor_positions proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_cursor_positions proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_visible_cursor_position proto  :ptr GtkTextIter
gtk_text_iter_backward_visible_cursor_position proto  :ptr GtkTextIter
gtk_text_iter_forward_visible_cursor_positions proto  :ptr GtkTextIter, :gint
gtk_text_iter_backward_visible_cursor_positions proto  :ptr GtkTextIter, :gint
gtk_text_iter_set_offset proto  :ptr GtkTextIter, :gint
gtk_text_iter_set_line proto  :ptr GtkTextIter, :gint
gtk_text_iter_set_line_offset proto  :ptr GtkTextIter, :gint
gtk_text_iter_set_line_index proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_to_end proto  :ptr GtkTextIter
gtk_text_iter_forward_to_line_end proto  :ptr GtkTextIter
gtk_text_iter_set_visible_line_offset proto  :ptr GtkTextIter, :gint
gtk_text_iter_set_visible_line_index proto  :ptr GtkTextIter, :gint
gtk_text_iter_forward_to_tag_toggle proto  :ptr GtkTextIter, :ptr GtkTextTag
gtk_text_iter_backward_to_tag_toggle proto  :ptr GtkTextIter, :ptr GtkTextTag
;proto_GtkTextCharPredicate typedef proto  :gunichar,:gpointer
;GtkTextCharPredicate typedef ptr proto_GtkTextCharPredicate
;gtk_text_iter_forward_find_char proto  :ptr GtkTextIter, :GtkTextCharPredicate, :gpointer, :ptr GtkTextIter
;gtk_text_iter_backward_find_char proto  :ptr GtkTextIter, :GtkTextCharPredicate, :gpointer, :ptr GtkTextIter
gtk_text_iter_forward_search proto  :ptr GtkTextIter, :ptr gchar, :GtkTextSearchFlags, :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_backward_search proto  :ptr GtkTextIter, :ptr gchar, :GtkTextSearchFlags, :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_equal proto  :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_compare proto  :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_in_range proto  :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_iter_order proto  :ptr GtkTextIter, :ptr GtkTextIter

;--- errors: 8
;--- end of file ---
