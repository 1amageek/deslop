// The subset of libIndexStore's C interface swift-deslop reads, declared as
// function pointer types. The library itself is loaded at run time, from the
// toolchain whose compiler wrote the index, so that the reader and the
// writer of the index always match.

#ifndef CINDEXSTORE_H
#define CINDEXSTORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef void *cis_indexstore_t;
typedef void *cis_error_t;
typedef void *cis_unit_reader_t;
typedef void *cis_unit_dependency_t;
typedef void *cis_record_reader_t;
typedef void *cis_occurrence_t;
typedef void *cis_symbol_t;
typedef void *cis_symbol_relation_t;

typedef struct {
  const char *data;
  size_t length;
} cis_string_ref_t;

enum {
  CIS_UNIT_DEPENDENCY_UNIT = 1,
  CIS_UNIT_DEPENDENCY_RECORD = 2,
  CIS_UNIT_DEPENDENCY_FILE = 3,
};

typedef bool (*cis_unit_name_applier_t)(void *context, cis_string_ref_t unit_name);
typedef bool (*cis_dependency_applier_t)(void *context, cis_unit_dependency_t dependency);
typedef bool (*cis_occurrence_applier_t)(void *context, cis_occurrence_t occurrence);
typedef bool (*cis_relation_applier_t)(void *context, cis_symbol_relation_t relation);

typedef const char *(*cis_error_get_description_f)(cis_error_t);
typedef void (*cis_error_dispose_f)(cis_error_t);

typedef cis_indexstore_t (*cis_store_create_f)(const char *store_path, cis_error_t *error);
typedef void (*cis_store_dispose_f)(cis_indexstore_t);
typedef bool (*cis_store_units_apply_f)(cis_indexstore_t, unsigned sorted, void *context,
                                        cis_unit_name_applier_t applier);

typedef cis_unit_reader_t (*cis_unit_reader_create_f)(cis_indexstore_t, const char *unit_name,
                                                      cis_error_t *error);
typedef void (*cis_unit_reader_dispose_f)(cis_unit_reader_t);
typedef bool (*cis_unit_reader_bool_f)(cis_unit_reader_t);
typedef cis_string_ref_t (*cis_unit_reader_string_f)(cis_unit_reader_t);
typedef void (*cis_unit_reader_get_modification_time_f)(cis_unit_reader_t, int64_t *seconds,
                                                        int64_t *nanoseconds);
typedef bool (*cis_unit_reader_dependencies_apply_f)(cis_unit_reader_t, void *context,
                                                     cis_dependency_applier_t applier);

typedef unsigned (*cis_unit_dependency_get_kind_f)(cis_unit_dependency_t);
typedef bool (*cis_unit_dependency_is_system_f)(cis_unit_dependency_t);
typedef cis_string_ref_t (*cis_unit_dependency_string_f)(cis_unit_dependency_t);

typedef cis_record_reader_t (*cis_record_reader_create_f)(cis_indexstore_t, const char *record_name,
                                                          cis_error_t *error);
typedef void (*cis_record_reader_dispose_f)(cis_record_reader_t);
typedef bool (*cis_record_reader_occurrences_apply_f)(cis_record_reader_t, void *context,
                                                      cis_occurrence_applier_t applier);

typedef cis_symbol_t (*cis_occurrence_get_symbol_f)(cis_occurrence_t);
typedef uint64_t (*cis_occurrence_get_roles_f)(cis_occurrence_t);
typedef void (*cis_occurrence_get_line_col_f)(cis_occurrence_t, unsigned *line, unsigned *column);
typedef bool (*cis_occurrence_relations_apply_f)(cis_occurrence_t, void *context,
                                                 cis_relation_applier_t applier);

typedef uint64_t (*cis_symbol_relation_get_roles_f)(cis_symbol_relation_t);
typedef cis_symbol_t (*cis_symbol_relation_get_symbol_f)(cis_symbol_relation_t);

typedef int (*cis_symbol_get_int_f)(cis_symbol_t);
typedef uint64_t (*cis_symbol_get_properties_f)(cis_symbol_t);
typedef cis_string_ref_t (*cis_symbol_get_string_f)(cis_symbol_t);

#endif
