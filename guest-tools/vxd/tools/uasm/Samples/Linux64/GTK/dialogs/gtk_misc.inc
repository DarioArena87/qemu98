GtkApplication TYPEDEF QWORD 
GtkWidget      TYPEDEF QWORD
GtkButton      TYPEDEF QWORD
GObjectClass   TYPEDEF QWORD
GObject        TYPEDEF QWORD
gpointer       TYPEDEF QWORD
gboolean       TYPEDEF QWORD

gint           TYPEDEF SDWORD

 
g_signal_connect_data PROTO :QWORD,:QWORD, :QWORD, :QWORD, :QWORD, :QWORD
gtk_window_set_default_size  PROTO :QWORD, :QWORD, :QWORD
g_application_run     PROTO :QWORD,:QWORD, :QWORD
gtk_application_window_new   PROTO :QWORD
gtk_application_new   PROTO :QWORD,:QWORD
gtk_window_set_title  PROTO :QWORD,:QWORD
gtk_widget_show_all   PROTO :QWORD
g_object_unref PROTO :QWORD
gtk_widget_show PROTO :QWORD 
gtk_grid_new  PROTO
gtk_entry_new PROTO
gtk_combo_box_text_new PROTO
gtk_combo_box_text_append_text PROTO :QWORD,:QWORD
gtk_combo_box_text_prepend_text  PROTO :QWORD,:QWORD  
gtk_container_add PROTO :QWORD,:QWORD
g_list_append PROTO :QWORD,:QWORD
gtk_text_view_new PROTO 
gtk_label_new PROTO :QWORD
gtk_button_new_with_label PROTO :QWORD
gtk_grid_attach PROTO :QWORD,:QWORD, :QWORD, :QWORD, :QWORD, :QWORD
gtk_combo_set_popdown_strings PROTO :QWORD,:QWORD
gtk_grid_set_row_spacing  PROTO :QWORD,:QWORD
gtk_grid_set_column_spacing  PROTO :QWORD,:QWORD 
gtk_widget_set_margin_left PROTO :QWORD,:QWORD
gtk_widget_set_halign PROTO :QWORD,:QWORD 
gtk_widget_set_valign PROTO :QWORD,:QWORD 
gtk_info_bar_new PROTO 
gtk_widget_set_no_show_all  PROTO :QWORD,:QWORD  
gtk_info_bar_add_button PROTO  :QWORD, :QWORD, :QWORD
gtk_widget_hide PROTO :QWORD 
gtk_window_set_resizable PROTO  :QWORD, :QWORD
gtk_widget_set_size_request PROTO :QWORD, :QWORD, :QWORD
gtk_label_set_single_line_mode  PROTO  :QWORD, :QWORD
gtk_label_set_markup PROTO  :QWORD, :QWORD 
gtk_label_set_markup PROTO  :QWORD, :QWORD 
gtk_combo_box_set_active_id  PROTO  :QWORD, :QWORD 
gtk_combo_box_set_active PROTO  :QWORD, :QWORD
gtk_entry_set_text PROTO  :QWORD, :QWORD
gtk_entry_set_max_length PROTO  :QWORD, :QWORD
gtk_text_view_set_buffer PROTO  :QWORD, :QWORD
gtk_text_view_new_with_buffer  PROTO  :QWORD
gtk_text_view_get_buffer PROTO :QWORD
gtk_widget_set_vexpand PROTO  :QWORD, :QWORD
gtk_scrollable_set_vscroll_policy PROTO  :QWORD, :QWORD
gtk_scrolled_window_new proto :QWORD , :QWORD 
gtk_scrolled_window_set_policy proto :QWORD , :QWORD , :QWORD 
gtk_scrolled_window_set_shadow_type proto :QWORD , :QWORD 
gtk_message_dialog_new   PROTO :QWORD,:QWORD, :QWORD, :QWORD, :QWORD, :VARARG
gtk_message_dialog_format_secondary_text  PROTO :QWORD,:QWORD, :VARARG
gtk_combo_box_get_active  PROTO :QWORD
gtk_text_view_get_buffer PROTO :QWORD
gtk_widget_destroy PROTO :QWORD
gtk_dialog_run PROTO :QWORD
gtk_entry_get_text PROTO :QWORD
gtk_main_quit PROTO
g_application_quit PROTO :QWORD
gtk_widget_destroy PROTO :QWORD
g_signal_connect_swapped PROTO :QWORD,:QWORD, :QWORD, :QWORD
gtk_dialog_new_with_buttons PROTO :QWORD,:QWORD, :QWORD, :QWORD, :VARARG
gtk_image_new_from_file  PROTO :QWORD
gtk_dialog_get_content_area PROTO :QWORD
gtk_box_pack_start PROTO :QWORD,:QWORD, :QWORD, :QWORD, :QWORD
gtk_vbox_new PROTO :QWORD,:QWORD
gtk_window_set_icon_from_file PROTO :QWORD,:QWORD, :QWORD


printf PROTO SYSTEMV pformat:PTR, arg:VARARG

 G_APPLICATION_FLAGS_NONE equ 0
 
  GTK_WINDOW_TOPLEVEL  EQU 0
  GTK_POLICY_AUTOMATIC EQU 1
  GTK_SHADOW_IN EQU 1

  GTK_ALIGN_FILL     equ 0
  GTK_ALIGN_START    equ 1
  GTK_ALIGN_END      equ 2
  GTK_ALIGN_CENTER   equ 3
  GTK_ALIGN_BASELINE equ 4
  
  GTK_SCROLL_MINIMUM  equ 0
  GTK_SCROLL_NATURAL  equ 1
  
  GTK_RESPONSE_NONE         equ -1
  GTK_RESPONSE_REJECT       equ -2
  GTK_RESPONSE_ACCEPT       equ -3
  GTK_RESPONSE_DELETE_EVENT equ -4
  GTK_RESPONSE_OK           equ -5
  GTK_RESPONSE_CANCEL       equ -6
  GTK_RESPONSE_CLOSE        equ -7
  GTK_RESPONSE_YES          equ -8
  GTK_RESPONSE_NO           equ -9
  GTK_RESPONSE_APPLY        equ -10
  GTK_RESPONSE_HELP         equ -11
  
  GTK_DIALOG_MODAL equ 1
  GTK_DIALOG_DESTROY_WITH_PARENT equ 2
 
  NULL  EQU 0
  TRUE  EQU 1
  FALSE EQU 0
