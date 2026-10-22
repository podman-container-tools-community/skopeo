/*
 * musl 1.2.4 removed the basename() declaration from string.h. containers/storage
 * before skopeo 1.16 calls it in pkg/unshare/unshare.c without including libgen.h,
 * and zig's clang refuses implicit declarations, so .goreleaser.yaml includes this file
 * into every cgo C file for those releases. Assembly files get CGO_CFLAGS too, and
 * libgen.h is not valid assembly, hence the guard. Delete it together with 1.15.
 */
#ifndef __ASSEMBLER__
#include <libgen.h>
#endif
