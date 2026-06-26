
; FILE: dialogs.asm
; DESC: Program demonstrates modal and nonmodal dialogs
; LINK: gcc ./dialogs.o -o ./dialogs `pkg-config --libs gtk+-3.0 gthread-2.0 gobject-2.0 gmodule-no-export-2.0`

; written for UASM by GoneFishing 25 December 2017
 
include gtk_misc.inc
include gtktextbuffer.inc
include gtktextiter.inc
 
.data 
        
     window    GtkWidget NULL
     entry     GtkWidget NULL
     textvu    GtkWidget NULL
     combobox1 GtkWidget NULL
     combobox2 GtkWidget NULL
     startiter GtkTextIter <>
     enditer   GtkTextIter <> 
 
     markup   db 10,'<span foreground="black" background="blue"  font="Nimbus Mono L" size="xx-large"><b>G</b></span>', 
                    '<span foreground="black" background="red"   font="Nimbus Mono L" size="xx-large"><b>T</b></span>',
                    '<span foreground="black" background="green" font="Nimbus Mono L" size="xx-large"><b>K</b></span>',
                    '<span foreground="black" background="white" font="Nimbus Mono L" size="xx-large"><b>3</b></span>',
                    '<span font="Nimbus Mono L" size="xx-large"><b> Dialogs                 </b></span> ',0                          
.code

main  PROC  argc:QWORD, argv:QWORD
      LOCAL app:GtkApplication 
      LOCAL status:DWORD
   
      mov app, RV(gtk_application_new , CStr("uasm.gtk.example"), G_APPLICATION_FLAGS_NONE)  
      invoke g_signal_connect_data,app, CStr("activate"), ADDR activate, NULL, NULL, NULL
      invoke g_application_run , app, 0 , 0 
      mov status, eax
      invoke g_object_unref, app
      mov eax, status 
      ret 
main  ENDP

activate PROC  app:GtkApplication, user_data:gpointer          
         LOCAL grid:GtkWidget 
         LOCAL lbl1:GtkWidget
         LOCAL buffer :GtkWidget
         LOCAL button1:GtkWidget
         LOCAL button2:GtkWidget
         LOCAL button3:GtkWidget 
         LOCAL scroll:GtkWidget 
         LOCAL dummy:QWORD            

         mov window , RV(gtk_application_window_new, app)
            
         invoke gtk_window_set_icon_from_file, window, CStr("./iching28.gif"),NULL 

;------- Create and setup grid
         
         mov grid, RV( gtk_grid_new )
         invoke gtk_container_add, window, grid             
         invoke gtk_widget_set_halign, grid, GTK_ALIGN_CENTER
         invoke gtk_widget_set_valign, grid,  GTK_ALIGN_START  
         invoke gtk_grid_set_row_spacing , grid ,20
         invoke gtk_grid_set_column_spacing, grid ,10         

;------- Create and setup label
             
         mov lbl1, RV(gtk_label_new,CStr(" ")) 
         invoke gtk_label_set_single_line_mode, lbl1, FALSE
         invoke gtk_label_set_markup , lbl1, ADDR markup
         invoke gtk_grid_attach, grid, lbl1, 0, 0, 2, 4  

;------- Create and setup comboboxes  
           
         mov combobox1, RV(gtk_combo_box_text_new)
         mov combobox2, RV(gtk_combo_box_text_new)
             
         invoke gtk_combo_box_text_append_text, combobox1, CStr("GTK_MESSAGE_INFO")
         invoke gtk_combo_box_text_append_text, combobox1, CStr("GTK_MESSAGE_WARNING")
         invoke gtk_combo_box_text_append_text, combobox1, CStr("GTK_MESSAGE_QUESTION")
         invoke gtk_combo_box_text_append_text, combobox1, CStr("GTK_MESSAGE_ERROR")
         invoke gtk_combo_box_text_append_text, combobox1, CStr("GTK_MESSAGE_OTHER")
             
         invoke gtk_combo_box_set_active , combobox1, 0   ; set default active element
         invoke gtk_grid_attach, grid, combobox1, 0, 4, 1, 1
             
         invoke gtk_combo_box_text_append_text, combobox2, CStr("GTK_BUTTONS_NONE")
         invoke gtk_combo_box_text_append_text, combobox2, CStr("GTK_BUTTONS_OK")
         invoke gtk_combo_box_text_append_text, combobox2, CStr("GTK_BUTTONS_CLOSE")
         invoke gtk_combo_box_text_append_text, combobox2, CStr("GTK_BUTTONS_CANCEL")
         invoke gtk_combo_box_text_append_text, combobox2, CStr("GTK_BUTTONS_YES_NO")
         invoke gtk_combo_box_text_append_text, combobox2, CStr("GTK_BUTTONS_OK_CANCEL")
             
         invoke gtk_combo_box_set_active , combobox2, 1   ; set default active element
         invoke gtk_grid_attach, grid, combobox2, 1, 4, 1, 1
   
;------- Create and setup entry
             
         mov entry, RV(gtk_entry_new)
         invoke gtk_entry_set_max_length, entry, 64
         invoke gtk_entry_set_text, entry, CStr("The title text is limited to 64 characters")
         invoke gtk_grid_attach, grid, entry, 0, 5, 2, 1

;------- Create and setup textview widget ( we have to create scrolled window to make our widget scrollable )
         
         mov scroll , RV(gtk_scrolled_window_new, NULL, NULL) 
     
         invoke gtk_scrolled_window_set_policy, scroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC
            
         invoke gtk_scrolled_window_set_shadow_type, scroll, GTK_SHADOW_IN  
         mov textvu,  RV( gtk_text_view_new )
         
         mov buffer, RV(gtk_text_view_get_buffer,textvu)
         invoke gtk_text_buffer_set_text, buffer ,  CStr("Message text is limited to 256 characters."), 42 
         invoke gtk_text_view_set_buffer, textvu, buffer 
             
         invoke gtk_grid_attach, grid, scroll, 0, 6, 2, 5
         invoke gtk_container_add, scroll , textvu
   
;------- Create and setup buttons
             
         mov button1, RV(gtk_button_new_with_label , CStr("Show Modal Dialog"))
         invoke g_signal_connect_data, button1, CStr("clicked",0), ADDR show_modal_clicked, NULL,NULL,NULL
         invoke gtk_grid_attach, grid, button1, 0, 11, 2, 1

         mov button2, RV(gtk_button_new_with_label , CStr("Show Nonmodal"))
         invoke g_signal_connect_data, button2, CStr("clicked",0), ADDR show_nonmodal_clicked, NULL,NULL,NULL
         invoke gtk_grid_attach, grid, button2, 0, 12, 1, 1
                
         mov button3, RV(gtk_button_new_with_label , CStr("Close"))
         invoke g_signal_connect_data, button3, CStr("clicked"), ADDR gtk_widget_destroy,window,NULL, 2 ; G_CONNECT_SWAPPED
         invoke gtk_grid_attach, grid, button3, 1, 12, 1, 1                 
       
;-------- Setup top level window 

         invoke gtk_window_set_title, window, CStr("GTK3 Dialogs")
       
         invoke gtk_widget_set_size_request, window, 420, 360
         invoke gtk_window_set_resizable, window, FALSE
         invoke gtk_widget_show_all, window
         ret
activate ENDP

show_modal_clicked PROC button:GtkButton,	user_data:gpointer
                   LOCAL dialog:GtkWidget, buffer:QWORD
                         
                   mov r14, RV(gtk_combo_box_get_active , combobox1)
                   mov r15, RV(gtk_combo_box_get_active , combobox2)
                   ; create modal dialog                         
                   mov dialog,RV(gtk_message_dialog_new, window,GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,r14, r15, RV(gtk_entry_get_text, entry))              
                   mov buffer, RV(gtk_text_view_get_buffer, textvu)
                   invoke printf, CStr(" buffer char count = %d",10),RV(gtk_text_buffer_get_char_count, buffer)
                   invoke gtk_text_buffer_get_start_iter,  buffer, ADDR startiter
                   invoke gtk_text_buffer_get_iter_at_offset, buffer, ADDR enditer, 256  ; limit the text length to 256 characters
                   invoke gtk_message_dialog_format_secondary_text, dialog, CStr("%s"), RV( gtk_text_buffer_get_text, buffer, ADDR startiter, ADDR enditer, FALSE) 
                   invoke gtk_dialog_run, dialog
                   invoke printf, CStr(" dialog response = %d",10), rax
                   invoke gtk_widget_destroy, dialog
                   ret
show_modal_clicked ENDP

show_nonmodal_clicked  PROC button:GtkButton,	user_data:gpointer
                       LOCAL nonmodal:GtkWidget , vbox:GtkWidget, lbl2:GtkWidget, image:GtkWidget, contentArea:GtkWidget 
                      
                       ; create nonmodal dialog  
                       mov nonmodal, RV(gtk_dialog_new_with_buttons, CStr("Hex 28 - Ta Kuo"), window,GTK_DIALOG_DESTROY_WITH_PARENT, CStr("OK",0),GTK_RESPONSE_ACCEPT,NULL)
                       mov vbox, RV(gtk_vbox_new,0,0)
                       mov lbl2,RV(gtk_label_new, CStr("Preponderance of the Great"))
                       mov image, RV(gtk_image_new_from_file,  CStr("./iching28.gif"))
                       mov contentArea,RV(gtk_dialog_get_content_area, nonmodal) ; get content area - GtkBox 
                       
                       invoke gtk_box_pack_start, vbox, image,0,0,0
                       invoke gtk_box_pack_start, vbox, lbl2,0,0,0
                       invoke gtk_box_pack_start,contentArea , vbox,0,0,0
                       invoke gtk_window_set_resizable, nonmodal, FALSE
                       invoke gtk_widget_show_all, nonmodal
                       invoke g_signal_connect_data, nonmodal, CStr("response"), ADDR nonmodal_dialog_result, NULL,NULL,NULL                            
                       ret
show_nonmodal_clicked  ENDP  

nonmodal_dialog_result PROC dialog:GtkWidget, response:gint, user_data:gpointer
                       invoke gtk_widget_destroy, dialog
                       ret 
nonmodal_dialog_result ENDP
                   
end  main
