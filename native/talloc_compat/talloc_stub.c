#include "talloc.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct TallocHeader {
	const void *parent;
	size_t size;
	size_t count;
} TallocHeader;

static TallocHeader *header_from_ptr(const void *ptr) {
	return ptr == NULL ? NULL : ((TallocHeader *)ptr) - 1;
}

static void *payload_from_header(TallocHeader *header) {
	return header == NULL ? NULL : (void *)(header + 1);
}

static void *alloc_with_header(const void *ctx, size_t size, size_t count, int zero) {
	if (size > SIZE_MAX - sizeof(TallocHeader)) return NULL;
	TallocHeader *header = zero
		? calloc(1, sizeof(TallocHeader) + size)
		: malloc(sizeof(TallocHeader) + size);
	if (header == NULL) return NULL;
	header->parent = ctx;
	header->size = size;
	header->count = count;
	return payload_from_header(header);
}

void *talloc_new(const void *ctx) { return talloc_zero_size(ctx, 1); }

void *talloc_size(const void *ctx, size_t size) {
	return alloc_with_header(ctx, size, 0, 0);
}

void *talloc_zero_size(const void *ctx, size_t size) {
	return alloc_with_header(ctx, size, 0, 1);
}

void *talloc_array_size(const void *ctx, size_t element_size, size_t count) {
	if (count != 0 && element_size > SIZE_MAX / count) return NULL;
	return alloc_with_header(ctx, element_size * count, count, 0);
}

void *talloc_zero_array_size(const void *ctx, size_t element_size, size_t count) {
	if (count != 0 && element_size > SIZE_MAX / count) return NULL;
	return alloc_with_header(ctx, element_size * count, count, 1);
}

void *talloc_realloc_size(const void *ctx, void *ptr, size_t size) {
	if (ptr == NULL) return talloc_size(ctx, size);
	if (size > SIZE_MAX - sizeof(TallocHeader)) return NULL;
	TallocHeader *new_header = realloc(header_from_ptr(ptr), sizeof(TallocHeader) + size);
	if (new_header == NULL) return NULL;
	new_header->parent = ctx;
	new_header->size = size;
	new_header->count = 0;
	return payload_from_header(new_header);
}

void *talloc_realloc_array_size(const void *ctx, void *ptr, size_t element_size, size_t count) {
	if (count != 0 && element_size > SIZE_MAX / count) return NULL;
	void *result = talloc_realloc_size(ctx, ptr, element_size * count);
	TallocHeader *header = header_from_ptr(result);
	if (header != NULL) header->count = count;
	return result;
}

char *talloc_strdup(const void *ctx, const char *value) {
	if (value == NULL) return NULL;
	size_t size = strlen(value) + 1;
	char *copy = talloc_size(ctx, size);
	if (copy == NULL) return NULL;
	memcpy(copy, value, size);
	return copy;
}

char *talloc_strndup(const void *ctx, const char *value, size_t size) {
	if (value == NULL) return NULL;
	size_t length = strnlen(value, size);
	char *copy = talloc_size(ctx, length + 1);
	if (copy == NULL) return NULL;
	memcpy(copy, value, length);
	copy[length] = '\0';
	return copy;
}

void *talloc_memdup(const void *ctx, const void *ptr, size_t size) {
	if (ptr == NULL) return NULL;
	void *copy = talloc_size(ctx, size);
	if (copy == NULL) return NULL;
	memcpy(copy, ptr, size);
	return copy;
}

const char *talloc_get_name(const void *ptr) { (void)ptr; return ""; }

size_t talloc_get_size(const void *ptr) {
	TallocHeader *header = header_from_ptr(ptr);
	return header == NULL ? 0 : header->size;
}

char *talloc_vasprintf(const void *ctx, const char *format, va_list args) {
	va_list copy;
	va_copy(copy, args);
	int length = vsnprintf(NULL, 0, format, copy);
	va_end(copy);
	if (length < 0) return NULL;
	char *buffer = talloc_size(ctx, (size_t)length + 1);
	if (buffer == NULL) return NULL;
	vsnprintf(buffer, (size_t)length + 1, format, args);
	return buffer;
}

char *talloc_asprintf(const void *ctx, const char *format, ...) {
	va_list args;
	va_start(args, format);
	char *result = talloc_vasprintf(ctx, format, args);
	va_end(args);
	return result;
}

void *talloc_parent(const void *ptr) {
	TallocHeader *header = header_from_ptr(ptr);
	return header == NULL ? NULL : (void *)header->parent;
}

size_t talloc_array_length(const void *ptr) {
	TallocHeader *header = header_from_ptr(ptr);
	return header == NULL ? 0 : header->count;
}

int talloc_free(void *ptr) { free(header_from_ptr(ptr)); return 0; }

void *talloc_autofree_context(void) { static int context; return &context; }

int talloc_unlink(const void *ctx, void *ptr) { (void)ctx; return talloc_free(ptr); }

void *talloc_reparent(const void *old_parent, const void *new_parent, const void *ptr) {
	(void)old_parent;
	TallocHeader *header = header_from_ptr(ptr);
	if (header != NULL) header->parent = new_parent;
	return (void *)ptr;
}

void *talloc_reference(const void *ctx, const void *ptr) {
	(void)ctx;
	return (void *)ptr;
}

size_t talloc_reference_count(const void *ptr) { (void)ptr; return 0; }

void talloc_report_depth_cb(
	const void *ptr,
	int depth,
	int max_depth,
	void (*callback)(const void *ptr, int depth, int max_depth, int is_ref, void *private_data),
	void *private_data
) {
	if (callback != NULL) callback(ptr, depth, max_depth, 0, private_data);
}

void talloc_report_depth_file(const void *ptr, int depth, int max_depth, FILE *file) {
	(void)ptr;
	(void)depth;
	(void)max_depth;
	(void)file;
}

void talloc_enable_leak_report(void) {}

void talloc_set_log_stderr(void) {}
