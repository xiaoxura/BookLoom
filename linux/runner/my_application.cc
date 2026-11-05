#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* file_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void file_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* call,
                                gpointer user_data) {
  if (strcmp(fl_method_call_get_name(call), "chooseSavePath") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(call);
  FlValue* name = args == nullptr ? nullptr : fl_value_lookup_string(args, "fileName");
  if (name == nullptr || fl_value_get_type(name) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(call, "invalid_name", "Missing file name", nullptr,
                                 nullptr);
    return;
  }

  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      "保存文件", GTK_WINDOW(user_data), GTK_FILE_CHOOSER_ACTION_SAVE, "保存",
      "取消");
  gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(dialog), TRUE);
  gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(dialog),
                                    fl_value_get_string(name));
  const gint response = gtk_native_dialog_run(GTK_NATIVE_DIALOG(dialog));
  gchar* path = response == GTK_RESPONSE_ACCEPT
                    ? gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog))
                    : nullptr;
  g_autoptr(FlValue) result = path == nullptr ? fl_value_new_null()
                                             : fl_value_new_string(path);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond_success(call, result, &error)) {
    g_warning("Failed to send save path: %s", error->message);
  }
  g_free(path);
  gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // The app draws its own title bar (see lib/app/shell/window_caption.dart),
  // so the window is frameless: dragging, window buttons and edge resizing all
  // come from Flutter.
  gtk_window_set_title(window, "书织 Bookloom");
  gtk_window_set_decorated(window, FALSE);

  // Desktop comfort: enough room for the sidebar plus a readable column.
  gtk_window_set_default_size(window, 1440, 900);
  gtk_widget_set_size_request(GTK_WIDGET(window), 820, 600);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  // Resolve inside the Flutter bundle, independent of the working directory.
  g_autofree gchar* icon_path = g_build_filename(
      fl_dart_project_get_assets_path(project), "assets", "brand",
      "bookloom-icon.png", nullptr);
  g_autoptr(GError) icon_error = nullptr;
  if (!gtk_window_set_icon_from_file(window, icon_path, &icon_error)) {
    g_warning("Failed to load application icon: %s", icon_error->message);
  }
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Match the paper canvas so startup never flashes black. Follows the GTK
  // theme so a dark desktop gets the dark paper.
  GtkSettings* gtk_settings = gtk_settings_get_default();
  gboolean prefer_dark = FALSE;
  g_object_get(gtk_settings, "gtk-application-prefer-dark-theme", &prefer_dark,
               nullptr);
  gdk_rgba_parse(&background_color, prefer_dark ? "#121110" : "#FBF7EF");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->file_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "bookloom/file_service", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->file_channel,
                                            file_method_call_cb, window,
                                            nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->file_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
