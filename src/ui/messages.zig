//! Message dialogs (information, warning, error and question).

const std = @import("std");
const gtk = @import("../bindings/gtk.zig");
const c = gtk.c;

const Title = [:0]const u8;

pub fn info(parent: gtk.Widget, title: []const u8, msg: []const u8) void {
    _ = show(parent, title, msg, c.GTK_MESSAGE_INFO, c.GTK_BUTTONS_OK, .ok);
}

pub fn warning(parent: gtk.Widget, title: []const u8, msg: []const u8) void {
    _ = show(parent, title, msg, c.GTK_MESSAGE_WARNING, c.GTK_BUTTONS_OK, .ok);
}

pub fn errorDialog(parent: gtk.Widget, title: []const u8, msg: []const u8) void {
    _ = show(parent, title, msg, c.GTK_MESSAGE_ERROR, c.GTK_BUTTONS_OK, .ok);
}

/// Shows a question with Yes/No answers.
pub fn question(parent: gtk.Widget, title: []const u8, msg: []const u8) bool {
    return show(parent, title, msg, c.GTK_MESSAGE_QUESTION, c.GTK_BUTTONS_YES_NO, .yes_no);
}

/// Shows a dialog with custom "Execute" / "Cancel" buttons.
pub fn confirm(parent: gtk.Widget, title: []const u8, msg: []const u8) bool {
    const dialog = c.gtk_message_dialog_new(
        parent,
        c.GTK_DIALOG_DESTROY_WITH_PARENT | c.GTK_DIALOG_MODAL,
        c.GTK_MESSAGE_QUESTION,
        c.GTK_BUTTONS_NONE,
        "%s",
        gtk.toC(msg),
    );
    c.gtk_window_set_title(dialog, gtk.toC(title));
    _ = c.gtk_dialog_add_button(dialog, "Execute", c.GTK_RESPONSE_OK);
    _ = c.gtk_dialog_add_button(dialog, "Cancel", c.GTK_RESPONSE_CANCEL);
    const response = c.gtk_dialog_run(dialog);
    c.gtk_widget_destroy(dialog);
    return response == c.GTK_RESPONSE_OK;
}

const Buttons = enum {
    ok,
    yes_no,
};

fn show(
    parent: gtk.Widget,
    title: []const u8,
    msg: []const u8,
    msg_type: c_int,
    buttons: c_int,
    kind: Buttons,
) bool {
    const dialog = c.gtk_message_dialog_new(
        parent,
        c.GTK_DIALOG_DESTROY_WITH_PARENT | c.GTK_DIALOG_MODAL,
        msg_type,
        buttons,
        "%s",
        gtk.toC(msg),
    );
    c.gtk_window_set_title(dialog, gtk.toC(title));
    c.gtk_window_set_position(dialog, c.GTK_WIN_POS_CENTER);

    const response = c.gtk_dialog_run(dialog);
    c.gtk_widget_destroy(dialog);

    return switch (kind) {
        .ok => true,
        .yes_no => response == c.GTK_RESPONSE_YES,
    };
}