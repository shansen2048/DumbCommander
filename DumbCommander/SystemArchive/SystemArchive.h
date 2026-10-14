#ifndef DUMBCOMMANDER_SYSTEM_ARCHIVE_H
#define DUMBCOMMANDER_SYSTEM_ARCHIVE_H
#include <sys/types.h>
#include <stdint.h>
#include <stddef.h>

/* Stable C ABI exposed by macOS libarchive. The SDK ships the library and manual
 * pages but not these public declarations. No implementation is vendored.
 * See docs/decisions/0006-sichere-dateimutationen.md. */
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_format_zip(struct archive *);
int archive_read_support_format_tar(struct archive *);
int archive_read_support_filter_none(struct archive *);
int archive_read_open_fd(struct archive *, int, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
time_t archive_entry_mtime(struct archive_entry *);
long archive_entry_mtime_nsec(struct archive_entry *);
#endif
