; FILE: example-0.asm
; READ: https://developer.gnome.org/gtk3/stable/gtk-getting-started.html#id-1.2.3.5
; LINK: gcc ./example-0.o -o ./example-0 `pkg-config --libs gtk+-3.0 gthread-2.0 gobject-2.0 gmodule-no-export-2.0`
; DESC: This program will create an empty 200 × 200 pixel window.

GtkApplication TYPEDEF QWORD 
GtkWidget      TYPEDEF QWORD
gpointer       TYPEDEF QWORD  
 
g_signal_connect_data PROTO :QWORD,:QWORD, :QWORD, :QWORD, :QWORD, :QWORD
gtk_window_set_default_size  PROTO :QWORD, :QWORD, :QWORD
g_application_run     PROTO :QWORD,:QWORD, :QWORD
gtk_application_window_new   PROTO :QWORD
gtk_application_new   PROTO :QWORD,:QWORD
gtk_window_set_title  PROTO :QWORD,:QWORD
gtk_widget_show_all   PROTO :QWORD
g_object_unref PROTO :QWORD

 G_APPLICATION_FLAGS_NONE equ 0
 
 NULL EQU 0
 
.code

main  PROC  argc:QWORD, argv:QWORD
      LOCAL app:GtkApplication, status:DWORD
   
      mov app, RV(gtk_application_new , CStr("uasm.gtk.example"), G_APPLICATION_FLAGS_NONE)  
      invoke g_signal_connect_data, app, CStr("activate"), ADDR activate, NULL, NULL, NULL
      invoke g_application_run , app, 0 , 0 
      mov status, eax
      invoke g_object_unref, app
      mov eax, status 
      ret 
main  ENDP

activate PROC  app:GtkApplication, user_data:gpointer 
         LOCAL window:GtkWidget

         mov window , RV(gtk_application_window_new, app)
         invoke gtk_window_set_title, window, CStr("Window")
         invoke gtk_window_set_default_size, window, 200, 200
         invoke gtk_widget_show_all, window
         ret
activate ENDP  
                    
end  main
