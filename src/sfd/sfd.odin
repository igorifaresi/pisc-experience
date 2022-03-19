package sfd

import "core:c"
import "core:os"

when os.OS == .Linux do foreign import sfd "libsfd.a"
when os.OS == .Windows {
	foreign import sfd {
		"sfd.lib",
		"system:comdlg32.lib",
	}
}

SFD_VERSION :: "0.1.0"

Options :: struct {
	title:       cstring,
	path:        cstring,
	filter_name: cstring,
	filter:      cstring,
	extension:   cstring,
}

@(default_calling_convention="c", link_prefix="sfd_")
foreign sfd {
	get_error   :: proc() -> cstring ---;
	open_dialog :: proc(ctx: ^Options) -> cstring ---;
	save_dialog :: proc(ctx: ^Options) -> cstring ---;
}