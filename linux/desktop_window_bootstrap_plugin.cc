#include "include/desktop_window_bootstrap/desktop_window_bootstrap_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

#include "desktop_window_bootstrap_plugin_private.h"

#define DESKTOP_WINDOW_BOOTSTRAP_PLUGIN(obj)                              \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), desktop_window_bootstrap_plugin_get_type(), \
                              DesktopWindowBootstrapPlugin))

struct _DesktopWindowBootstrapPlugin {
  GObject parent_instance;
};

static double g_red = 0.0;
static double g_green = 0.0;
static double g_blue = 0.0;
static double g_alpha = 0.0;
static FlPluginRegistrar* g_registrar = nullptr;

G_DEFINE_TYPE(
    DesktopWindowBootstrapPlugin,
    desktop_window_bootstrap_plugin,
    g_object_get_type())

static gboolean DrawCallback(GtkWidget* widget, cairo_t* cr, gpointer data) {
  cairo_save(cr);
  cairo_set_source_rgba(cr, g_red, g_green, g_blue, g_alpha);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_paint(cr);
  cairo_restore(cr);
  return FALSE;
}

static void ApplyTransparentBackground() {
  FlView* view = fl_plugin_registrar_get_view(g_registrar);
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_widget_hide(GTK_WIDGET(window));
  gtk_widget_hide(GTK_WIDGET(view));
  g_red = 0.0;
  g_green = 0.0;
  g_blue = 0.0;
  g_alpha = 0.0;
  gtk_widget_show(GTK_WIDGET(window));
  gtk_widget_show(GTK_WIDGET(view));
}

static void desktop_window_bootstrap_plugin_handle_method_call(
    DesktopWindowBootstrapPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "initialize") == 0) {
    ApplyTransparentBackground();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "getTitlebarInset") == 0) {
    g_autoptr(FlValue) result = fl_value_new_float(0.0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void desktop_window_bootstrap_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(desktop_window_bootstrap_plugin_parent_class)->dispose(object);
}

static void desktop_window_bootstrap_plugin_class_init(
    DesktopWindowBootstrapPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = desktop_window_bootstrap_plugin_dispose;
}

static void desktop_window_bootstrap_plugin_init(DesktopWindowBootstrapPlugin* self) {}

static void method_call_cb(
  FlMethodChannel* channel,
  FlMethodCall* method_call,
  gpointer user_data) {
  DesktopWindowBootstrapPlugin* plugin =
      DESKTOP_WINDOW_BOOTSTRAP_PLUGIN(user_data);
  desktop_window_bootstrap_plugin_handle_method_call(plugin, method_call);
}

void desktop_window_bootstrap_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  DesktopWindowBootstrapPlugin* plugin = DESKTOP_WINDOW_BOOTSTRAP_PLUGIN(
      g_object_new(desktop_window_bootstrap_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "desktop_window_bootstrap/methods",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel,
      method_call_cb,
      g_object_ref(plugin),
      g_object_unref);

  FlView* view = fl_plugin_registrar_get_view(registrar);
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);

  GdkScreen* screen = gdk_screen_get_default();
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }
  g_signal_connect(G_OBJECT(window), "draw", G_CALLBACK(DrawCallback), nullptr);
  gtk_widget_show(GTK_WIDGET(window));
  gtk_widget_show(GTK_WIDGET(view));

  g_registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  g_object_unref(plugin);
}
