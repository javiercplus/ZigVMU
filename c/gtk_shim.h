/*
 * gtk_shim.h - Minimal manual GTK3 binding.
 *
 * Declares only the opaque types, constants and functions the application
 * needs. It avoids @cImport of the full GTK headers, which the Zig 0.16 C
 * translator does not process reliably.
 *
 * All widget parameters are typed as GtkWidget*, since GtkWidget is the
 * common base and the ABI is an opaque pointer in every case.
 */

#ifndef ZIGVMU_GTK_SHIM_H
#define ZIGVMU_GTK_SHIM_H

/* --- Tipos base --- */
typedef int gboolean;
typedef int gint;
typedef unsigned int guint;
typedef unsigned long gulong;
typedef double gdouble;
typedef float gfloat;
typedef void *gpointer;
typedef const void *gconstpointer;
typedef void (*GCallback)(void);
typedef gboolean (*GSourceFunc)(gpointer user_data);

/* --- Tipos opacos de GObject/GTK --- */
typedef struct _GtkApplication GtkApplication;
typedef struct _GApplication GApplication;
typedef struct _GtkWidget GtkWidget;
typedef struct _GtkAdjustment GtkAdjustment;

/* --- Constantes --- */
#define G_APPLICATION_FLAGS_NONE 0
#define G_CONNECT_DEFAULT 0

#define GTK_WINDOW_TOPLEVEL 0
#define GTK_WINDOW_POPUP 1
#define GTK_WIN_POS_NONE 0
#define GTK_WIN_POS_CENTER 1

#define GTK_ORIENTATION_HORIZONTAL 0
#define GTK_ORIENTATION_VERTICAL 1

#define GTK_ALIGN_FILL 0
#define GTK_ALIGN_START 1
#define GTK_ALIGN_END 2
#define GTK_ALIGN_CENTER 3

#define GTK_PACK_START 0
#define GTK_PACK_END 1

#define GTK_RESPONSE_NONE -1
#define GTK_RESPONSE_REJECT -2
#define GTK_RESPONSE_ACCEPT -3
#define GTK_RESPONSE_DELETE_EVENT -4
#define GTK_RESPONSE_OK -5
#define GTK_RESPONSE_CANCEL -6
#define GTK_RESPONSE_CLOSE -7
#define GTK_RESPONSE_YES -8
#define GTK_RESPONSE_NO -9
#define GTK_RESPONSE_APPLY -10
#define GTK_RESPONSE_HELP -11

#define GTK_DIALOG_MODAL 1
#define GTK_DIALOG_DESTROY_WITH_PARENT 2

#define GTK_MESSAGE_INFO 0
#define GTK_MESSAGE_WARNING 1
#define GTK_MESSAGE_QUESTION 2
#define GTK_MESSAGE_ERROR 3

#define GTK_BUTTONS_NONE 0
#define GTK_BUTTONS_OK 1
#define GTK_BUTTONS_CLOSE 2
#define GTK_BUTTONS_CANCEL 3
#define GTK_BUTTONS_YES_NO 4
#define GTK_BUTTONS_OK_CANCEL 5

#define GTK_FILE_CHOOSER_ACTION_OPEN 0
#define GTK_FILE_CHOOSER_ACTION_SAVE 1
#define GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER 2
#define GTK_FILE_CHOOSER_ACTION_CREATE_FOLDER 3

/* --- GObject / GApplication --- */
GtkApplication *gtk_application_new(const char *application_id, int flags);
int g_application_run(GApplication *application, int argc, char **argv);
void g_application_quit(GApplication *application);
void g_object_unref(gpointer object);
void g_object_ref_sink(gpointer object);
gulong g_signal_connect_data(gpointer instance, const char *detailed_signal,
                             GCallback c_handler, gpointer data,
                             gpointer destroy_data, int connect_flags);
void g_free(gpointer mem);

/* --- Fuentes e idle --- */
guint g_idle_add(GSourceFunc function, gpointer data);
guint g_timeout_add(guint interval, GSourceFunc function, gpointer data);
gboolean g_source_remove(guint tag);

/* --- Ventanas --- */
GtkWidget *gtk_application_window_new(GtkApplication *application);
void gtk_application_add_window(GtkApplication *application, GtkWidget *window);
void gtk_window_set_title(GtkWidget *window, const char *title);
void gtk_window_set_default_size(GtkWidget *window, int width, int height);
void gtk_window_set_resizable(GtkWidget *window, gboolean resizable);
void gtk_window_set_modal(GtkWidget *window, gboolean modal);
void gtk_window_set_transient_for(GtkWidget *window, GtkWidget *parent);
void gtk_window_set_position(GtkWidget *window, int position);

/* --- Widgets base --- */
void gtk_widget_show(GtkWidget *widget);
void gtk_widget_hide(GtkWidget *widget);
void gtk_widget_show_all(GtkWidget *widget);
void gtk_widget_destroy(GtkWidget *widget);
void gtk_widget_set_sensitive(GtkWidget *widget, gboolean sensitive);
void gtk_widget_set_margin_start(GtkWidget *widget, int margin);
void gtk_widget_set_margin_end(GtkWidget *widget, int margin);
void gtk_widget_set_margin_top(GtkWidget *widget, int margin);
void gtk_widget_set_margin_bottom(GtkWidget *widget, int margin);
void gtk_widget_set_halign(GtkWidget *widget, int align);
void gtk_widget_set_valign(GtkWidget *widget, int align);
void gtk_widget_set_hexpand(GtkWidget *widget, gboolean expand);
void gtk_widget_set_vexpand(GtkWidget *widget, gboolean expand);
void gtk_widget_set_size_request(GtkWidget *widget, int width, int height);

/* --- Contenedores --- */
void gtk_container_add(GtkWidget *container, GtkWidget *widget);
void gtk_container_set_border_width(GtkWidget *container, guint border_width);
GtkWidget *gtk_box_new(int orientation, int spacing);
void gtk_box_pack_start(GtkWidget *box, GtkWidget *child, gboolean expand,
                        gboolean fill, guint padding);
void gtk_box_pack_end(GtkWidget *box, GtkWidget *child, gboolean expand,
                      gboolean fill, guint padding);
GtkWidget *gtk_grid_new(void);
void gtk_grid_attach(GtkWidget *grid, GtkWidget *child, int left, int top,
                     int width, int height);
void gtk_grid_set_row_spacing(GtkWidget *grid, guint spacing);
void gtk_grid_set_column_spacing(GtkWidget *grid, guint spacing);
void gtk_grid_set_row_homogeneous(GtkWidget *grid, gboolean homogeneous);
void gtk_grid_set_column_homogeneous(GtkWidget *grid, gboolean homogeneous);
GtkWidget *gtk_separator_new(int orientation);

/* --- Etiquetas --- */
GtkWidget *gtk_label_new(const char *text);
void gtk_label_set_text(GtkWidget *label, const char *text);
void gtk_label_set_markup(GtkWidget *label, const char *markup);
void gtk_label_set_xalign(GtkWidget *label, float xalign);
void gtk_label_set_yalign(GtkWidget *label, float yalign);
void gtk_label_set_selectable(GtkWidget *label, gboolean selectable);
void gtk_label_set_line_wrap(GtkWidget *label, gboolean wrap);

/* --- Botones --- */
GtkWidget *gtk_button_new_with_label(const char *label);
void gtk_button_set_label(GtkWidget *button, const char *label);

/* --- Entradas --- */
GtkWidget *gtk_entry_new(void);
void gtk_entry_set_text(GtkWidget *entry, const char *text);
const char *gtk_entry_get_text(GtkWidget *entry);
void gtk_entry_set_placeholder_text(GtkWidget *entry, const char *text);

/* --- Spins --- */
GtkAdjustment *gtk_adjustment_new(double value, double lower, double upper,
                                  double step_increment, double page_increment,
                                  double page_size);
GtkWidget *gtk_spin_button_new(GtkAdjustment *adjustment, double climb_rate,
                               guint digits);
int gtk_spin_button_get_value_as_int(GtkWidget *spin);
void gtk_spin_button_set_value(GtkWidget *spin, double value);
void gtk_spin_button_set_increments(GtkWidget *spin, double step, double page);

/* --- Checkboxes --- */
GtkWidget *gtk_check_button_new_with_label(const char *label);
gboolean gtk_toggle_button_get_active(GtkWidget *toggle);
void gtk_toggle_button_set_active(GtkWidget *toggle, gboolean active);

/* --- Botones de radio --- */
GtkWidget *gtk_radio_button_new_with_label(void *group, const char *label);
GtkWidget *gtk_radio_button_new_with_label_from_widget(GtkWidget *radio_group_member,
                                                      const char *label);

/* --- Combos --- */
GtkWidget *gtk_combo_box_text_new(void);
void gtk_combo_box_text_append_text(GtkWidget *combo, const char *text);
int gtk_combo_box_get_active(GtkWidget *combo);
void gtk_combo_box_set_active(GtkWidget *combo, int index);
char *gtk_combo_box_text_get_active_text(GtkWidget *combo);

/* --- Selector de archivos --- */
GtkWidget *gtk_file_chooser_button_new(const char *title, int action);
gboolean gtk_file_chooser_set_filename(GtkWidget *chooser, const char *filename);
char *gtk_file_chooser_get_filename(GtkWidget *chooser);

/* --- Barras de progreso --- */
GtkWidget *gtk_progress_bar_new(void);
void gtk_progress_bar_set_fraction(GtkWidget *bar, double fraction);
void gtk_progress_bar_set_text(GtkWidget *bar, const char *text);
void gtk_progress_bar_set_show_text(GtkWidget *bar, gboolean show_text);
void gtk_progress_bar_pulse(GtkWidget *bar);
void gtk_progress_bar_set_pulse_step(GtkWidget *bar, double fraction);

/* --- Dialogos --- */
GtkWidget *gtk_dialog_new(void);
GtkWidget *gtk_dialog_add_button(GtkWidget *dialog, const char *button_text,
                                 int response_id);
int gtk_dialog_run(GtkWidget *dialog);
GtkWidget *gtk_dialog_get_content_area(GtkWidget *dialog);
void gtk_dialog_set_default_response(GtkWidget *dialog, int response_id);
GtkWidget *gtk_message_dialog_new(GtkWidget *parent, int flags, int type,
                                  int buttons, const char *message_format, ...);

/* --- CSS (no rounded corners) --- */
#define GTK_STYLE_PROVIDER_PRIORITY_APPLICATION 600
void *gtk_css_provider_new(void);
void gtk_css_provider_load_from_data(void *css_provider, const char *data,
                                     long length, void **error);
void *gdk_screen_get_default(void);
void gtk_style_context_add_provider_for_screen(void *screen, void *provider,
                                               guint priority);

#endif /* ZIGVMU_GTK_SHIM_H */
