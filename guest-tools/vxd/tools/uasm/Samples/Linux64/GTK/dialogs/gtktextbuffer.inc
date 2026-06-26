;--- include file created by h2incx v0.99.20 (copyright 2005-2009 japheth)

;* This is the PUBLIC representation of a text buffer.
;* GtkTextBTree is the PRIVATE internal representation of it.
;*
;* these values are used as "info" for the targets contained in the
;* lists returned by gtk_text_buffer_get_copy,paste_target_list()
;*
;* the enum counts down from G_MAXUINT to avoid clashes with application
;* added drag destinations which usually start at 0.

GtkTextBufferTargetInfo typedef DWORD
GTK_TEXT_BUFFER_TARGET_INFO_BUFFER_CONTENTS = - 1 
GTK_TEXT_BUFFER_TARGET_INFO_RICH_TEXT = - 2 
GTK_TEXT_BUFFER_TARGET_INFO_TEXT = - 3 

;GtkTextBTree typedef _GtkTextBTree

GTK_TYPE_TEXT_BUFFER	EQU	<( gtk_text_buffer_get_type ( ) )>
GTK_TEXT_BUFFER macro obj
	exitm <( G_TYPE_CHECK_INSTANCE_CAST ( ( obj ) , GTK_TYPE_TEXT_BUFFER , GtkTextBuffer ) ) >
	endm
GTK_TEXT_BUFFER_CLASS macro klass
	exitm <( G_TYPE_CHECK_CLASS_CAST ( ( klass ) , GTK_TYPE_TEXT_BUFFER , GtkTextBufferClass ) ) >
	endm
GTK_IS_TEXT_BUFFER macro obj
	exitm <( G_TYPE_CHECK_INSTANCE_TYPE ( ( obj ) , GTK_TYPE_TEXT_BUFFER ) ) >
	endm
GTK_IS_TEXT_BUFFER_CLASS macro klass
	exitm <( G_TYPE_CHECK_CLASS_TYPE ( ( klass ) , GTK_TYPE_TEXT_BUFFER ) ) >
	endm
GTK_TEXT_BUFFER_GET_CLASS macro obj
	exitm <( G_TYPE_INSTANCE_GET_CLASS ( ( obj ) , GTK_TYPE_TEXT_BUFFER , GtkTextBufferClass ) ) >
	endm
;GtkTextBufferPrivate typedef _GtkTextBufferPrivate

;GtkTextBufferClass typedef _GtkTextBufferClass

_GtkTextBuffer	struct 
parent_instance	GObject	?
priv	DWORD	?
_GtkTextBuffer	ends

_GtkTextBufferClass	struct 
parent_class	GObjectClass	?
proto_GtkTextBufferClass_insert_text typedef proto  :ptr GtkTextBuffer,:ptr GtkTextIter,:ptr const,:gint
p_GtkTextBufferClass_insert_text typedef ptr proto_GtkTextBufferClass_insert_text
insert_text	p_GtkTextBufferClass_insert_text	?
proto_GtkTextBufferClass_insert_pixbuf typedef proto  :ptr GtkTextBuffer,:ptr GtkTextIter,:ptr GdkPixbuf
p_GtkTextBufferClass_insert_pixbuf typedef ptr proto_GtkTextBufferClass_insert_pixbuf
insert_pixbuf	p_GtkTextBufferClass_insert_pixbuf	?
proto_GtkTextBufferClass_insert_child_anchor typedef proto  :ptr GtkTextBuffer,:ptr GtkTextIter,:ptr GtkTextChildAnchor
p_GtkTextBufferClass_insert_child_anchor typedef ptr proto_GtkTextBufferClass_insert_child_anchor
insert_child_anchor	p_GtkTextBufferClass_insert_child_anchor	?
proto_GtkTextBufferClass_delete_range typedef proto  :ptr GtkTextBuffer,:ptr GtkTextIter,:ptr GtkTextIter
p_GtkTextBufferClass_delete_range typedef ptr proto_GtkTextBufferClass_delete_range
delete_range	p_GtkTextBufferClass_delete_range	?
;* Only for text/widgets/pixbuf changed, marks/tags don't cause this
;* to be emitted
;*
proto_GtkTextBufferClass_changed typedef proto  :ptr GtkTextBuffer
p_GtkTextBufferClass_changed typedef ptr proto_GtkTextBufferClass_changed
changed	p_GtkTextBufferClass_changed	?
;* New value for the modified flag *
proto_GtkTextBufferClass_modified_changed typedef proto  :ptr GtkTextBuffer
p_GtkTextBufferClass_modified_changed typedef ptr proto_GtkTextBufferClass_modified_changed
modified_changed	p_GtkTextBufferClass_modified_changed	?
;* Mark moved or created *
proto_GtkTextBufferClass_mark_set typedef proto  :ptr GtkTextBuffer,:ptr const,:ptr GtkTextMark
p_GtkTextBufferClass_mark_set typedef ptr proto_GtkTextBufferClass_mark_set
mark_set	p_GtkTextBufferClass_mark_set	?
proto_GtkTextBufferClass_mark_deleted typedef proto  :ptr GtkTextBuffer,:ptr GtkTextMark
p_GtkTextBufferClass_mark_deleted typedef ptr proto_GtkTextBufferClass_mark_deleted
mark_deleted	p_GtkTextBufferClass_mark_deleted	?
proto_GtkTextBufferClass_apply_tag typedef proto  :ptr GtkTextBuffer,:ptr GtkTextTag,:ptr const,:ptr const
p_GtkTextBufferClass_apply_tag typedef ptr proto_GtkTextBufferClass_apply_tag
apply_tag	p_GtkTextBufferClass_apply_tag	?
proto_GtkTextBufferClass_remove_tag typedef proto  :ptr GtkTextBuffer,:ptr GtkTextTag,:ptr const,:ptr const
p_GtkTextBufferClass_remove_tag typedef ptr proto_GtkTextBufferClass_remove_tag
remove_tag	p_GtkTextBufferClass_remove_tag	?
;* Called at the start and end of an atomic user action *
proto_GtkTextBufferClass_begin_user_action typedef proto  :ptr GtkTextBuffer
p_GtkTextBufferClass_begin_user_action typedef ptr proto_GtkTextBufferClass_begin_user_action
begin_user_action	p_GtkTextBufferClass_begin_user_action	?
proto_GtkTextBufferClass_end_user_action typedef proto  :ptr GtkTextBuffer
p_GtkTextBufferClass_end_user_action typedef ptr proto_GtkTextBufferClass_end_user_action
end_user_action	p_GtkTextBufferClass_end_user_action	?
proto_GtkTextBufferClass_paste_done typedef proto  :ptr GtkTextBuffer,:ptr GtkClipboard
p_GtkTextBufferClass_paste_done typedef ptr proto_GtkTextBufferClass_paste_done
paste_done	p_GtkTextBufferClass_paste_done	?
;* Padding for future expansion *
proto_GtkTextBufferClass__gtk_reserved1 typedef proto  ;:void
p_GtkTextBufferClass__gtk_reserved1 typedef ptr proto_GtkTextBufferClass__gtk_reserved1
_gtk_reserved1	p_GtkTextBufferClass__gtk_reserved1	?
proto_GtkTextBufferClass__gtk_reserved2 typedef proto  ;:void
p_GtkTextBufferClass__gtk_reserved2 typedef ptr proto_GtkTextBufferClass__gtk_reserved2
_gtk_reserved2	p_GtkTextBufferClass__gtk_reserved2	?
proto_GtkTextBufferClass__gtk_reserved3 typedef proto  ;:void
p_GtkTextBufferClass__gtk_reserved3 typedef ptr proto_GtkTextBufferClass__gtk_reserved3
_gtk_reserved3	p_GtkTextBufferClass__gtk_reserved3	?
proto_GtkTextBufferClass__gtk_reserved4 typedef proto  ;:void
p_GtkTextBufferClass__gtk_reserved4 typedef ptr proto_GtkTextBufferClass__gtk_reserved4
_gtk_reserved4	p_GtkTextBufferClass__gtk_reserved4	?
_GtkTextBufferClass	ends


GtkTextBufferClass typedef _GtkTextBufferClass

gtk_text_buffer_get_type proto  ;:void
;* table is NULL to create a new one *
gtk_text_buffer_new proto  :ptr GtkTextTagTable
gtk_text_buffer_get_line_count proto  :ptr GtkTextBuffer
gtk_text_buffer_get_char_count proto  :ptr GtkTextBuffer
gtk_text_buffer_get_tag_table proto  :ptr GtkTextBuffer
;* Delete whole buffer, then insert *
gtk_text_buffer_set_text proto  :ptr GtkTextBuffer, :ptr gchar, :gint
;* Insert into the buffer *
gtk_text_buffer_insert proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr gchar, :gint
gtk_text_buffer_insert_at_cursor proto  :ptr GtkTextBuffer, :ptr gchar, :gint
gtk_text_buffer_insert_interactive proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr gchar, :gint, :gboolean
gtk_text_buffer_insert_interactive_at_cursor proto  :ptr GtkTextBuffer, :ptr gchar, :gint, :gboolean
gtk_text_buffer_insert_range proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_insert_range_interactive proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter, :gboolean
gtk_text_buffer_insert_with_tags proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr gchar, :gint, :ptr GtkTextTag, :VARARG
gtk_text_buffer_insert_with_tags_by_name proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr gchar, :gint, :ptr gchar, :VARARG
;* Delete from the buffer *
gtk_text_buffer_delete proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_delete_interactive proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter, :gboolean
gtk_text_buffer_backspace proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :gboolean, :gboolean
;* Obtain strings from the buffer *
gtk_text_buffer_get_text proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter, :gboolean
gtk_text_buffer_get_slice proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter, :gboolean
;* Insert a pixbuf *
gtk_text_buffer_insert_pixbuf proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GdkPixbuf
;* Insert a child anchor *
gtk_text_buffer_insert_child_anchor proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextChildAnchor
;* Convenience, create and insert a child anchor *
gtk_text_buffer_create_child_anchor proto  :ptr GtkTextBuffer, :ptr GtkTextIter
;* Mark manipulation *
gtk_text_buffer_add_mark proto  :ptr GtkTextBuffer, :ptr GtkTextMark, :ptr GtkTextIter
gtk_text_buffer_create_mark proto  :ptr GtkTextBuffer, :ptr gchar, :ptr GtkTextIter, :gboolean
gtk_text_buffer_move_mark proto  :ptr GtkTextBuffer, :ptr GtkTextMark, :ptr GtkTextIter
gtk_text_buffer_delete_mark proto  :ptr GtkTextBuffer, :ptr GtkTextMark
gtk_text_buffer_get_mark proto  :ptr GtkTextBuffer, :ptr gchar
gtk_text_buffer_move_mark_by_name proto  :ptr GtkTextBuffer, :ptr gchar, :ptr GtkTextIter
gtk_text_buffer_delete_mark_by_name proto  :ptr GtkTextBuffer, :ptr gchar
gtk_text_buffer_get_insert proto  :ptr GtkTextBuffer
gtk_text_buffer_get_selection_bound proto  :ptr GtkTextBuffer
;* efficiently move insert and selection_bound at the same time *
gtk_text_buffer_place_cursor proto  :ptr GtkTextBuffer, :ptr GtkTextIter
gtk_text_buffer_select_range proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter
;* Tag manipulation *
gtk_text_buffer_apply_tag proto  :ptr GtkTextBuffer, :ptr GtkTextTag, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_remove_tag proto  :ptr GtkTextBuffer, :ptr GtkTextTag, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_apply_tag_by_name proto  :ptr GtkTextBuffer, :ptr gchar, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_remove_tag_by_name proto  :ptr GtkTextBuffer, :ptr gchar, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_remove_all_tags proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter
;* You can either ignore the return value, or use it to
;* set the attributes of the tag. tag_name can be NULL
;*
gtk_text_buffer_create_tag proto  :ptr GtkTextBuffer, :ptr gchar, :ptr gchar, :VARARG
;* Obtain iterators pointed at various places, then you can move the
;* iterator around using the GtkTextIter operators
;*
gtk_text_buffer_get_iter_at_line_offset proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :gint, :gint
gtk_text_buffer_get_iter_at_line_index proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :gint, :gint
gtk_text_buffer_get_iter_at_offset proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :gint
gtk_text_buffer_get_iter_at_line proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :gint
gtk_text_buffer_get_start_iter proto  :ptr GtkTextBuffer, :ptr GtkTextIter
gtk_text_buffer_get_end_iter proto  :ptr GtkTextBuffer, :ptr GtkTextIter
gtk_text_buffer_get_bounds proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_get_iter_at_mark proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextMark
gtk_text_buffer_get_iter_at_child_anchor proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextChildAnchor
;* There's no get_first_iter because you just get the iter for
;line or char 0 *
;* Used to keep track of whether the buffer needs saving; anytime the
;buffer contents change, the modified flag is turned on. Whenever
;you save, turn it off. Tags and marks do not affect the modified
;flag, but if you would like them to you can connect a handler to
;the tag/mark signals and call set_modified in your handler *
gtk_text_buffer_get_modified proto  :ptr GtkTextBuffer
gtk_text_buffer_set_modified proto  :ptr GtkTextBuffer, :gboolean
gtk_text_buffer_get_has_selection proto  :ptr GtkTextBuffer
gtk_text_buffer_add_selection_clipboard proto  :ptr GtkTextBuffer, :ptr GtkClipboard
gtk_text_buffer_remove_selection_clipboard proto  :ptr GtkTextBuffer, :ptr GtkClipboard
gtk_text_buffer_cut_clipboard proto  :ptr GtkTextBuffer, :ptr GtkClipboard, :gboolean
gtk_text_buffer_copy_clipboard proto  :ptr GtkTextBuffer, :ptr GtkClipboard
gtk_text_buffer_paste_clipboard proto  :ptr GtkTextBuffer, :ptr GtkClipboard, :ptr GtkTextIter, :gboolean
gtk_text_buffer_get_selection_bounds proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr GtkTextIter
gtk_text_buffer_delete_selection proto  :ptr GtkTextBuffer, :gboolean, :gboolean
;* Called to specify atomic user actions, used to implement undo *
gtk_text_buffer_begin_user_action proto  :ptr GtkTextBuffer
gtk_text_buffer_end_user_action proto  :ptr GtkTextBuffer
gtk_text_buffer_get_copy_target_list proto  :ptr GtkTextBuffer
gtk_text_buffer_get_paste_target_list proto  :ptr GtkTextBuffer
;* INTERNAL private stuff *
_gtk_text_buffer_spew proto  :ptr GtkTextBuffer
_gtk_text_buffer_get_btree proto  :ptr GtkTextBuffer
_gtk_text_buffer_get_line_log_attrs proto  :ptr GtkTextBuffer, :ptr GtkTextIter, :ptr gint
_gtk_text_buffer_notify_will_remove_tag proto  :ptr GtkTextBuffer, :ptr GtkTextTag
;_gtk_text_buffer_get_text_before proto  :ptr GtkTextBuffer, :AtkTextBoundary, :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter
;_gtk_text_buffer_get_text_at proto  :ptr GtkTextBuffer, :AtkTextBoundary, :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter
;_gtk_text_buffer_get_text_after proto  :ptr GtkTextBuffer, :AtkTextBoundary, :ptr GtkTextIter, :ptr GtkTextIter, :ptr GtkTextIter

;--- errors: 0
;--- end of file ---
