#ifndef DRAXON_TALLOC_COMPAT_H
#define DRAXON_TALLOC_COMPAT_H

#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

typedef void TALLOC_CTX;

#define TALLOC_VERSION_MAJOR 2
#define talloc(ctx, type) ((type *)talloc_size((ctx), sizeof(type)))
#define talloc_zero(ctx, type) ((type *)talloc_zero_size((ctx), sizeof(type)))
#define talloc_array(ctx, type, count) \
	((type *)talloc_array_size((ctx), sizeof(type), (count)))
#define talloc_zero_array(ctx, type, count) \
	((type *)talloc_zero_array_size((ctx), sizeof(type), (count)))
#define talloc_realloc(ctx, ptr, type, count) \
	((type *)talloc_realloc_array_size((ctx), (ptr), sizeof(type), (count)))
#define talloc_get_type_abort(ptr, type) ((type *)(ptr))
#define talloc_get_type(ptr, type) ((type *)(ptr))
#define talloc_set_name_const(ptr, name) ((void)(ptr), (void)(name))
#define talloc_set_destructor(ptr, destructor) ((void)(ptr), (void)(destructor))
#define talloc_strdup_append_buffer(ptr, suffix) talloc_asprintf(NULL, "%s%s", (ptr), (suffix))

void *talloc_size(const void *ctx, size_t size);
void *talloc_zero_size(const void *ctx, size_t size);
void *talloc_array_size(const void *ctx, size_t element_size, size_t count);
void *talloc_zero_array_size(const void *ctx, size_t element_size, size_t count);
void *talloc_realloc_size(const void *ctx, void *ptr, size_t size);
void *talloc_realloc_array_size(
	const void *ctx,
	void *ptr,
	size_t element_size,
	size_t count
);
void *talloc_new(const void *ctx);
void *talloc_memdup(const void *ctx, const void *ptr, size_t size);
char *talloc_strdup(const void *ctx, const char *value);
char *talloc_strndup(const void *ctx, const char *value, size_t size);
char *talloc_asprintf(const void *ctx, const char *format, ...);
char *talloc_vasprintf(const void *ctx, const char *format, va_list args);
void *talloc_parent(const void *ptr);
void *talloc_autofree_context(void);
int talloc_unlink(const void *ctx, void *ptr);
void *talloc_reparent(const void *old_parent, const void *new_parent, const void *ptr);
void *talloc_reference(const void *ctx, const void *ptr);
void talloc_report_depth_cb(
	const void *ptr,
	int depth,
	int max_depth,
	void (*callback)(
		const void *ptr,
		int depth,
		int max_depth,
		int is_ref,
		void *private_data
	),
	void *private_data
);
const char *talloc_get_name(const void *ptr);
size_t talloc_get_size(const void *ptr);
void talloc_report_depth_file(
	const void *ptr,
	int depth,
	int max_depth,
	FILE *file
);
size_t talloc_reference_count(const void *ptr);
size_t talloc_array_length(const void *ptr);
int talloc_free(void *ptr);
void talloc_enable_leak_report(void);
void talloc_set_log_stderr(void);

#endif
