/*
   +----------------------------------------------------------------------+
   | Zend Engine                                                          |
   +----------------------------------------------------------------------+
   | Copyright (c) Zend Technologies Ltd. (http://www.zend.com)           |
   +----------------------------------------------------------------------+
   | This source file is subject to version 2.00 of the Zend license,     |
   | that is bundled with this package in the file LICENSE, and is        |
   | available through the world-wide-web at the following url:           |
   | http://www.zend.com/license/2_00.txt.                                |
   | If you did not receive a copy of the Zend license and are unable to  |
   | obtain it through the world-wide-web, please send a note to          |
   | license@zend.com so we can mail you a copy immediately.              |
   +----------------------------------------------------------------------+
   | Authors: Andi Gutmans <andi@php.net>                                 |
   |          Zeev Suraski <zeev@php.net>                                 |
   |          Nikita Popov <nikic@php.net>                                |
   +----------------------------------------------------------------------+
*/

#include <zend_language_parser.h>
#include "zend.h"
#include "zend_ast.h"
#include "zend_attributes.h"
#include "zend_compile.h"
#include "zend_constants.h"
#include "zend_llist.h"
#include "zend_API.h"
#include "zend_exceptions.h"
#include "zend_interfaces.h"
#include "zend_types.h"
#include "zend_virtual_cwd.h"
#include "zend_multibyte.h"
#include "zend_language_scanner.h"
#include "zend_inheritance.h"
#include "zend_vm.h"
#include "zend_enum.h"
#include "zend_observer.h"
#include "zend_call_stack.h"
#include "zend_frameless_function.h"
#include "zend_property_hooks.h"

#define SET_NODE(target, src) do { \
		target ## _type = (src)->op_type; \
		if ((src)->op_type == IS_CONST) { \
			target.constant = zend_add_literal(&(src)->u.constant); \
		} else { \
			target = (src)->u.op; \
		} \
	} while (0)

#define GET_NODE(target, src) do { \
		(target)->op_type = src ## _type; \
		if ((target)->op_type == IS_CONST) { \
			ZVAL_COPY_VALUE(&(target)->u.constant, CT_CONSTANT(src)); \
		} else { \
			(target)->u.op = src; \
		} \
	} while (0)

#define FC(member) (CG(file_context).member)

typedef struct _zend_loop_var {
	uint8_t opcode;
	uint8_t var_type;
	uint32_t   var_num;
	uint32_t   try_catch_offset;
} zend_loop_var;

static inline uint32_t zend_alloc_cache_slots(unsigned count) {
	if (count == 0) {
		/* Even if no cache slots are desired, the VM handler may still want to acquire
		 * CACHE_ADDR() unconditionally. Returning zero makes sure that the address
		 * calculation is still legal and ubsan does not complain. */
		return 0;
	}

	zend_op_array *op_array = CG(active_op_array);
	uint32_t ret = op_array->cache_size;
	op_array->cache_size += count * sizeof(void*);
	return ret;
}

static inline uint32_t zend_alloc_cache_slot(void) {
	return zend_alloc_cache_slots(1);
}

ZEND_API zend_op_array *(*zend_compile_file)(zend_file_handle *file_handle, int type);
ZEND_API zend_op_array *(*zend_compile_string)(zend_string *source_string, const char *filename, zend_compile_position position);

#ifndef ZTS
ZEND_API zend_compiler_globals compiler_globals;
ZEND_API zend_executor_globals executor_globals;
#endif

static zend_op *zend_emit_op(znode *result, uint8_t opcode, znode *op1, znode *op2);
static bool zend_try_ct_eval_array(zval *result, zend_ast *ast);
static void zend_eval_const_expr(zend_ast **ast_ptr);

static zend_op *zend_compile_var(znode *result, zend_ast *ast, uint32_t type, bool by_ref);
static zend_op *zend_delayed_compile_var(znode *result, zend_ast *ast, uint32_t type, bool by_ref);
static void zend_compile_expr(znode *result, zend_ast *ast);
static void zend_compile_stmt(zend_ast *ast);
static void zend_compile_assign(znode *result, zend_ast *ast, bool stmt, uint32_t type);

#ifdef ZEND_CHECK_STACK_LIMIT
zend_never_inline static void zend_stack_limit_error(void)
{
	size_t max_stack_size = 0;
	if ((uintptr_t) EG(stack_base) > (uintptr_t) EG(stack_limit)) {
		max_stack_size = (size_t) ((uintptr_t) EG(stack_base) - (uintptr_t) EG(stack_limit));
	}

	zend_error_noreturn(E_COMPILE_ERROR,
		"Maximum call stack size of %zu bytes (zend.max_allowed_stack_size - zend.reserved_stack_size) reached during compilation. Try splitting expression",
		max_stack_size);
}

static void zend_check_stack_limit(void)
{
	if (UNEXPECTED(zend_call_stack_overflowed(EG(stack_limit)))) {
		zend_stack_limit_error();
	}
}
#else /* ZEND_CHECK_STACK_LIMIT */
static void zend_check_stack_limit(void)
{
}
#endif /* ZEND_CHECK_STACK_LIMIT */

static void init_op(zend_op *op)
{
	MAKE_NOP(op);
	op->extended_value = 0;
	op->lineno = CG(zend_lineno);
#ifdef ZEND_VERIFY_TYPE_INFERENCE
	op->op1_use_type = 0;
	op->op2_use_type = 0;
	op->result_use_type = 0;
	op->op1_def_type = 0;
	op->op2_def_type = 0;
	op->result_def_type = 0;
#endif
}

static zend_always_inline uint32_t get_next_op_number(void)
{
	return CG(active_op_array)->last;
}

static zend_op *get_next_op(void)
{
	zend_op_array *op_array = CG(active_op_array);
	uint32_t next_op_num = op_array->last++;
	zend_op *next_op;

	if (UNEXPECTED(next_op_num >= CG(context).opcodes_size)) {
		CG(context).opcodes_size *= 4;
		op_array->opcodes = erealloc(op_array->opcodes, CG(context).opcodes_size * sizeof(zend_op));
	}

	next_op = &(op_array->opcodes[next_op_num]);

	init_op(next_op);

	return next_op;
}

static zend_brk_cont_element *get_next_brk_cont_element(void)
{
	CG(context).last_brk_cont++;
	CG(context).brk_cont_array = erealloc(CG(context).brk_cont_array, sizeof(zend_brk_cont_element) * CG(context).last_brk_cont);
	return &CG(context).brk_cont_array[CG(context).last_brk_cont-1];
}

static zend_string *zend_build_runtime_definition_key(zend_string *name, uint32_t start_lineno) /* {{{ */
{
	zend_string *filename = CG(active_op_array)->filename;
	zend_string *result = zend_strpprintf(0, "%c%s%s:%" PRIu32 "$%" PRIx32,
		'\0', ZSTR_VAL(name), ZSTR_VAL(filename), start_lineno, CG(rtd_key_counter)++);
	return zend_new_interned_string(result);
}
/* }}} */

static bool zend_get_unqualified_name(const zend_string *name, const char **result, size_t *result_len) /* {{{ */
{
	const char *ns_separator = zend_memrchr(ZSTR_VAL(name), '\\', ZSTR_LEN(name));
	if (ns_separator != NULL) {
		*result = ns_separator + 1;
		*result_len = ZSTR_VAL(name) + ZSTR_LEN(name) - *result;
		return 1;
	}

	return 0;
}
/* }}} */

struct reserved_class_name {
	const char *name;
	size_t len;
};
static const struct reserved_class_name reserved_class_names[] = {
	{ZEND_STRL("bool")},
	{ZEND_STRL("false")},
	{ZEND_STRL("float")},
	{ZEND_STRL("int")},
	{ZEND_STRL("null")},
	{ZEND_STRL("parent")},
	{ZEND_STRL("self")},
	{ZEND_STRL("static")},
	{ZEND_STRL("string")},
	{ZEND_STRL("true")},
	{ZEND_STRL("void")},
	{ZEND_STRL("never")},
	{ZEND_STRL("iterable")},
	{ZEND_STRL("object")},
	{ZEND_STRL("mixed")},
	/* These are not usable as class names because they're proper tokens,
	 * but they are here for class aliases. */
	{ZEND_STRL("array")},
	{ZEND_STRL("callable")},
	{NULL, 0}
};

static bool zend_is_reserved_class_name(const zend_string *name) /* {{{ */
{
	const struct reserved_class_name *reserved = reserved_class_names;

	const char *uqname = ZSTR_VAL(name);
	size_t uqname_len = ZSTR_LEN(name);
	zend_get_unqualified_name(name, &uqname, &uqname_len);

	for (; reserved->name; ++reserved) {
		if (uqname_len == reserved->len
			&& zend_binary_strcasecmp(uqname, uqname_len, reserved->name, reserved->len) == 0
		) {
			return 1;
		}
	}

	return 0;
}
/* }}} */

void zend_assert_valid_class_name(const zend_string *name, const char *type) /* {{{ */
{
	if (zend_is_reserved_class_name(name)) {
		zend_error_noreturn(E_COMPILE_ERROR,
			"Cannot use \"%s\" as %s as it is reserved", ZSTR_VAL(name), type);
	}
	if (zend_string_equals_literal(name, "_")) {
		zend_error(E_DEPRECATED, "Using \"_\" as %s is deprecated since 8.4", type);
	}
}
/* }}} */

typedef struct _builtin_type_info {
	const char* name;
	const size_t name_len;
	const uint8_t type;
} builtin_type_info;

static const builtin_type_info builtin_types[] = {
	{ZEND_STRL("null"), IS_NULL},
	{ZEND_STRL("true"), IS_TRUE},
	{ZEND_STRL("false"), IS_FALSE},
	{ZEND_STRL("int"), IS_LONG},
	{ZEND_STRL("float"), IS_DOUBLE},
	{ZEND_STRL("string"), IS_STRING},
	{ZEND_STRL("bool"), _IS_BOOL},
	{ZEND_STRL("void"), IS_VOID},
	{ZEND_STRL("never"), IS_NEVER},
	{ZEND_STRL("iterable"), IS_ITERABLE},
	{ZEND_STRL("object"), IS_OBJECT},
	{ZEND_STRL("mixed"), IS_MIXED},
	{NULL, 0, IS_UNDEF}
};

typedef struct {
	const char *name;
	size_t name_len;
	const char *correct_name;
} confusable_type_info;

static const confusable_type_info confusable_types[] = {
	{ZEND_STRL("boolean"), "bool"},
	{ZEND_STRL("integer"), "int"},
	{ZEND_STRL("double"), "float"},
	{ZEND_STRL("resource"), NULL},
	{NULL, 0, NULL},
};

static zend_always_inline uint8_t zend_lookup_builtin_type_by_name(const zend_string *name) /* {{{ */
{
	const builtin_type_info *info = &builtin_types[0];

	for (; info->name; ++info) {
		if (ZSTR_LEN(name) == info->name_len
			&& zend_binary_strcasecmp(ZSTR_VAL(name), ZSTR_LEN(name), info->name, info->name_len) == 0
		) {
			return info->type;
		}
	}

	return 0;
}
/* }}} */

static zend_always_inline bool zend_is_confusable_type(const zend_string *name, const char **correct_name) /* {{{ */
{
	const confusable_type_info *info = confusable_types;

	/* Intentionally using case-sensitive comparison here, because "integer" is likely intended
	 * as a scalar type, while "Integer" is likely a class type. */
	for (; info->name; ++info) {
		if (zend_string_equals_cstr(name, info->name, info->name_len)) {
			*correct_name = info->correct_name;
			return 1;
		}
	}

	return 0;
}
/* }}} */

static bool zend_is_not_imported(zend_string *name) {
	/* Assuming "name" is unqualified here. */
	return !FC(imports) || zend_hash_find_ptr_lc(FC(imports), name) == NULL;
}

void zend_oparray_context_begin(zend_oparray_context *prev_context, zend_op_array *op_array) /* {{{ */
{
	*prev_context = CG(context);
	CG(context).prev = CG(context).op_array ? prev_context : NULL;
	CG(context).op_array = op_array;
	CG(context).opcodes_size = INITIAL_OP_ARRAY_SIZE;
	CG(context).vars_size = 0;
	CG(context).literals_size = 0;
	CG(context).fast_call_var = -1;
	CG(context).try_catch_offset = -1;
	CG(context).current_brk_cont = -1;
	CG(context).last_brk_cont = 0;
	CG(context).has_assigned_to_http_response_header = false;
	CG(context).brk_cont_array = NULL;
	CG(context).labels = NULL;
	CG(context).in_jmp_frameless_branch = false;
	CG(context).active_property_info_name = NULL;
	CG(context).active_property_hook_kind = (zend_property_hook_kind)-1;
}
/* }}} */

void zend_oparray_context_end(const zend_oparray_context *prev_context) /* {{{ */
{
	if (CG(context).brk_cont_array) {
		efree(CG(context).brk_cont_array);
		CG(context).brk_cont_array = NULL;
	}
	if (CG(context).labels) {
		zend_hash_destroy(CG(context).labels);
		FREE_HASHTABLE(CG(context).labels);
		CG(context).labels = NULL;
	}
	CG(context) = *prev_context;
}
/* }}} */

static void zend_reset_import_tables(void) /* {{{ */
{
	if (FC(imports)) {
		zend_hash_destroy(FC(imports));
		efree(FC(imports));
		FC(imports) = NULL;
	}

	if (FC(imports_function)) {
		zend_hash_destroy(FC(imports_function));
		efree(FC(imports_function));
		FC(imports_function) = NULL;
	}

	if (FC(imports_const)) {
		zend_hash_destroy(FC(imports_const));
		efree(FC(imports_const));
		FC(imports_const) = NULL;
	}

	zend_hash_clean(&FC(seen_symbols));
}
/* }}} */

static void zend_end_namespace(void) /* {{{ */ {
	FC(in_namespace) = 0;
	zend_reset_import_tables();
	if (FC(current_namespace)) {
		zend_string_release_ex(FC(current_namespace), 0);
		FC(current_namespace) = NULL;
	}
}
/* }}} */

void zend_file_context_begin(zend_file_context *prev_context) /* {{{ */
{
	*prev_context = CG(file_context);
	FC(imports) = NULL;
	FC(imports_function) = NULL;
	FC(imports_const) = NULL;
	FC(current_namespace) = NULL;
	FC(in_namespace) = 0;
	FC(has_bracketed_namespaces) = 0;
	FC(declarables).ticks = 0;
	zend_hash_init(&FC(seen_symbols), 8, NULL, NULL, 0);
}
/* }}} */

void zend_file_context_end(const zend_file_context *prev_context) /* {{{ */
{
	zend_end_namespace();
	zend_hash_destroy(&FC(seen_symbols));
	CG(file_context) = *prev_context;
}
/* }}} */

void zend_init_compiler_data_structures(void) /* {{{ */
{
	zend_stack_init(&CG(loop_var_stack), sizeof(zend_loop_var));
	zend_stack_init(&CG(delayed_oplines_stack), sizeof(zend_op));
	zend_stack_init(&CG(short_circuiting_opnums), sizeof(uint32_t));
	CG(active_class_entry) = NULL;
	CG(in_compilation) = 0;
	CG(skip_shebang) = 0;

	CG(encoding_declared) = 0;
	CG(memoized_exprs) = NULL;
	CG(memoize_mode) = ZEND_MEMOIZE_NONE;
}
/* }}} */

static void zend_register_seen_symbol(zend_string *name, uint32_t kind) {
	zval *zv = zend_hash_find(&FC(seen_symbols), name);
	if (zv) {
		Z_LVAL_P(zv) |= kind;
	} else {
		zval tmp;
		ZVAL_LONG(&tmp, kind);
		zend_hash_add_new(&FC(seen_symbols), name, &tmp);
	}
}

static bool zend_have_seen_symbol(zend_string *name, uint32_t kind) {
	const zval *zv = zend_hash_find(&FC(seen_symbols), name);
	return zv && (Z_LVAL_P(zv) & kind) != 0;
}

void init_compiler(void) /* {{{ */
{
	CG(arena) = zend_arena_create(64 * 1024);
	CG(active_op_array) = NULL;
	memset(&CG(context), 0, sizeof(CG(context)));
	zend_init_compiler_data_structures();
	zend_init_rsrc_list();
	zend_stream_init();
	CG(unclean_shutdown) = 0;

	CG(delayed_variance_obligations) = NULL;
	CG(delayed_autoloads) = NULL;
	CG(unlinked_uses) = NULL;
	CG(current_linking_class) = NULL;
}
/* }}} */

void shutdown_compiler(void) /* {{{ */
{
	/* Reset filename before destroying the arena, as file cache may use arena allocated strings. */
	zend_restore_compiled_filename(NULL);

	zend_stack_destroy(&CG(loop_var_stack));
	zend_stack_destroy(&CG(delayed_oplines_stack));
	zend_stack_destroy(&CG(short_circuiting_opnums));

	if (CG(delayed_variance_obligations)) {
		zend_hash_destroy(CG(delayed_variance_obligations));
		FREE_HASHTABLE(CG(delayed_variance_obligations));
		CG(delayed_variance_obligations) = NULL;
	}
	if (CG(delayed_autoloads)) {
		zend_hash_destroy(CG(delayed_autoloads));
		FREE_HASHTABLE(CG(delayed_autoloads));
		CG(delayed_autoloads) = NULL;
	}
	if (CG(unlinked_uses)) {
		zend_hash_destroy(CG(unlinked_uses));
		FREE_HASHTABLE(CG(unlinked_uses));
		CG(unlinked_uses) = NULL;
	}
	CG(current_linking_class) = NULL;
}
/* }}} */

ZEND_API zend_string *zend_set_compiled_filename(zend_string *new_compiled_filename) /* {{{ */
{
	CG(compiled_filename) = zend_string_copy(new_compiled_filename);
	return new_compiled_filename;
}
/* }}} */

ZEND_API void zend_restore_compiled_filename(zend_string *original_compiled_filename) /* {{{ */
{
	if (CG(compiled_filename)) {
		zend_string_release(CG(compiled_filename));
		CG(compiled_filename) = NULL;
	}
	CG(compiled_filename) = original_compiled_filename;
}
/* }}} */

ZEND_API zend_string *zend_get_compiled_filename(void) /* {{{ */
{
	return CG(compiled_filename);
}
/* }}} */

ZEND_API uint32_t zend_get_compiled_lineno(void) /* {{{ */
{
	return CG(zend_lineno);
}
/* }}} */

ZEND_API bool zend_is_compiling(void) /* {{{ */
{
	return CG(in_compilation);
}
/* }}} */

static zend_always_inline uint32_t get_temporary_variable(void) /* {{{ */
{
	return (uint32_t)CG(active_op_array)->T++;
}
/* }}} */

static uint32_t lookup_cv(zend_string *name) /* {{{ */{
	zend_op_array *op_array = CG(active_op_array);
	int i = 0;
	zend_ulong hash_value = zend_string_hash_val(name);

	while (i < op_array->last_var) {
		if (ZSTR_H(op_array->vars[i]) == hash_value
		 && zend_string_equals(op_array->vars[i], name)) {
			return EX_NUM_TO_VAR(i);
		}
		i++;
	}
	i = op_array->last_var;
	op_array->last_var++;
	if (op_array->last_var > CG(context).vars_size) {
		CG(context).vars_size += 16; /* FIXME */
		op_array->vars = erealloc(op_array->vars, CG(context).vars_size * sizeof(zend_string*));
	}

	op_array->vars[i] = zend_string_copy(name);
	return EX_NUM_TO_VAR(i);
}
/* }}} */

zend_string *zval_make_interned_string(zval *zv)
{
	ZEND_ASSERT(Z_TYPE_P(zv) == IS_STRING);
	Z_STR_P(zv) = zend_new_interned_string(Z_STR_P(zv));
	if (ZSTR_IS_INTERNED(Z_STR_P(zv))) {
		Z_TYPE_FLAGS_P(zv) = 0;
	}
	return Z_STR_P(zv);
}

/* Common part of zend_add_literal and zend_append_individual_literal */
static inline void zend_insert_literal(const zend_op_array *op_array, zval *zv, int literal_position) /* {{{ */
{
	zval *lit = CT_CONSTANT_EX(op_array, literal_position);
	if (Z_TYPE_P(zv) == IS_STRING) {
		zval_make_interned_string(zv);
	}
	ZVAL_COPY_VALUE(lit, zv);
	Z_EXTRA_P(lit) = 0;
}
/* }}} */

/* Is used while compiling a function, using the context to keep track
   of an approximate size to avoid to relocate to often.
   Literals are truncated to actual size in the second compiler pass (pass_two()). */
static int zend_add_literal(zval *zv) /* {{{ */
{
	zend_op_array *op_array = CG(active_op_array);
	uint32_t i = op_array->last_literal;
	op_array->last_literal++;
	if (i >= CG(context).literals_size) {
		while (i >= CG(context).literals_size) {
			CG(context).literals_size += 16; /* FIXME */
		}
		op_array->literals = (zval*)erealloc(op_array->literals, CG(context).literals_size * sizeof(zval));
	}
	zend_insert_literal(op_array, zv, i);
	return i;
}
/* }}} */

static inline int zend_add_literal_string(zend_string **str) /* {{{ */
{
	int ret;
	zval zv;
	ZVAL_STR(&zv, *str);
	ret = zend_add_literal(&zv);
	*str = Z_STR(zv);
	return ret;
}
/* }}} */

static int zend_add_func_name_literal(zend_string *name) /* {{{ */
{
	/* Original name */
	int ret = zend_add_literal_string(&name);

	/* Lowercased name */
	zend_string *lc_name = zend_string_tolower(name);
	zend_add_literal_string(&lc_name);

	return ret;
}
/* }}} */

static int zend_add_ns_func_name_literal(zend_string *name) /* {{{ */
{
	const char *unqualified_name;
	size_t unqualified_name_len;

	/* Original name */
	int ret = zend_add_literal_string(&name);

	/* Lowercased name */
	zend_string *lc_name = zend_string_tolower(name);
	zend_add_literal_string(&lc_name);

	/* Lowercased unqualified name */
	if (zend_get_unqualified_name(name, &unqualified_name, &unqualified_name_len)) {
		lc_name = zend_string_alloc(unqualified_name_len, 0);
		zend_str_tolower_copy(ZSTR_VAL(lc_name), unqualified_name, unqualified_name_len);
		zend_add_literal_string(&lc_name);
	}

	return ret;
}
/* }}} */

static int zend_add_class_name_literal(zend_string *name) /* {{{ */
{
	/* Original name */
	int ret = zend_add_literal_string(&name);

	/* Lowercased name */
	zend_string *lc_name = zend_string_tolower(name);
	zend_add_literal_string(&lc_name);

	return ret;
}
/* }}} */

static int zend_add_const_name_literal(zend_string *name, bool unqualified) /* {{{ */
{
	zend_string *tmp_name;

	int ret = zend_add_literal_string(&name);

	size_t ns_len = 0, after_ns_len = ZSTR_LEN(name);
	const char *after_ns = zend_memrchr(ZSTR_VAL(name), '\\', ZSTR_LEN(name));
	if (after_ns) {
		after_ns += 1;
		ns_len = after_ns - ZSTR_VAL(name) - 1;
		after_ns_len = ZSTR_LEN(name) - ns_len - 1;

		/* lowercased namespace name & original constant name */
		tmp_name = zend_string_init(ZSTR_VAL(name), ZSTR_LEN(name), 0);
		zend_str_tolower(ZSTR_VAL(tmp_name), ns_len);
		zend_add_literal_string(&tmp_name);

		if (!unqualified) {
			return ret;
		}
	} else {
		after_ns = ZSTR_VAL(name);
	}

	/* original unqualified constant name */
	tmp_name = zend_string_init(after_ns, after_ns_len, 0);
	zend_add_literal_string(&tmp_name);

	return ret;
}
/* }}} */

#define LITERAL_STR(op, str) do { \
		zval _c; \
		ZVAL_STR(&_c, str); \
		op.constant = zend_add_literal(&_c); \
	} while (0)

void zend_stop_lexing(void)
{
	if (LANG_SCNG(on_event)) {
		LANG_SCNG(on_event)(ON_STOP, END, 0, NULL, 0, LANG_SCNG(on_event_context));
	}

	LANG_SCNG(yy_cursor) = LANG_SCNG(yy_limit);
}

static inline void zend_begin_loop(
		uint8_t free_opcode, const znode *loop_var, bool is_switch) /* {{{ */
{
	zend_brk_cont_element *brk_cont_element;
	int parent = CG(context).current_brk_cont;
	zend_loop_var info = {0};

	CG(context).current_brk_cont = CG(context).last_brk_cont;
	brk_cont_element = get_next_brk_cont_element();
	brk_cont_element->parent = parent;
	brk_cont_element->is_switch = is_switch;

	if (loop_var && (loop_var->op_type & (IS_VAR|IS_TMP_VAR))) {
		uint32_t start = get_next_op_number();

		info.opcode = free_opcode;
		info.var_type = loop_var->op_type;
		info.var_num = loop_var->u.op.var;
		brk_cont_element->start = start;
	} else {
		info.opcode = ZEND_NOP;
		/* The start field is used to free temporary variables in case of exceptions.
		 * We won't try to free something of we don't have loop variable.  */
		brk_cont_element->start = -1;
	}

	zend_stack_push(&CG(loop_var_stack), &info);
}
/* }}} */

static inline void zend_end_loop(int cont_addr, const znode *var_node) /* {{{ */
{
	uint32_t end = get_next_op_number();
	zend_brk_cont_element *brk_cont_element
		= &CG(context).brk_cont_array[CG(context).current_brk_cont];
	brk_cont_element->cont = cont_addr;
	brk_cont_element->brk = end;
	CG(context).current_brk_cont = brk_cont_element->parent;

	zend_stack_del_top(&CG(loop_var_stack));
}
/* }}} */

bool zend_op_may_elide_result(uint8_t opcode)
{
	switch (opcode) {
		case ZEND_ASSIGN:
		case ZEND_ASSIGN_DIM:
		case ZEND_ASSIGN_OBJ:
		case ZEND_ASSIGN_STATIC_PROP:
		case ZEND_ASSIGN_OP:
		case ZEND_ASSIGN_DIM_OP:
		case ZEND_ASSIGN_OBJ_OP:
		case ZEND_ASSIGN_STATIC_PROP_OP:
		case ZEND_PRE_INC_STATIC_PROP:
		case ZEND_PRE_DEC_STATIC_PROP:
		case ZEND_PRE_INC_OBJ:
		case ZEND_PRE_DEC_OBJ:
		case ZEND_PRE_INC:
		case ZEND_PRE_DEC:
		case ZEND_DO_FCALL:
		case ZEND_DO_ICALL:
		case ZEND_DO_UCALL:
		case ZEND_DO_FCALL_BY_NAME:
		case ZEND_YIELD:
		case ZEND_YIELD_FROM:
		case ZEND_INCLUDE_OR_EVAL:
			return true;
		default:
			return false;
	}
}

static void zend_do_free(znode *op1) /* {{{ */
{
	if (op1->op_type == IS_TMP_VAR) {
		zend_op *opline = &CG(active_op_array)->opcodes[CG(active_op_array)->last-1];

		while (opline->opcode == ZEND_END_SILENCE ||
		       opline->opcode == ZEND_OP_DATA) {
			opline--;
		}

		if (opline->result_type == IS_TMP_VAR && opline->result.var == op1->u.op.var) {
			switch (opline->opcode) {
				case ZEND_BOOL:
				case ZEND_BOOL_NOT:
					/* boolean results don't have to be freed */
					return;
				case ZEND_POST_INC_STATIC_PROP:
				case ZEND_POST_DEC_STATIC_PROP:
				case ZEND_POST_INC_OBJ:
				case ZEND_POST_DEC_OBJ:
				case ZEND_POST_INC:
				case ZEND_POST_DEC:
					/* convert $i++ to ++$i */
					opline->opcode -= 2;
					SET_UNUSED(opline->result);
					return;
				default:
					if (zend_op_may_elide_result(opline->opcode)) {
						SET_UNUSED(opline->result);
						return;
					}
					break;
			}
		}

		zend_emit_op(NULL, ZEND_FREE, op1, NULL);
	} else if (op1->op_type == IS_VAR) {
		zend_op *opline = &CG(active_op_array)->opcodes[CG(active_op_array)->last-1];
		while (opline->opcode == ZEND_END_SILENCE ||
				opline->opcode == ZEND_EXT_FCALL_END ||
				opline->opcode == ZEND_OP_DATA) {
			opline--;
		}
		if (opline->result_type == IS_VAR
			&& opline->result.var == op1->u.op.var) {
			if (opline->opcode == ZEND_FETCH_THIS) {
				opline->opcode = ZEND_NOP;
			}
			if (!ZEND_OP_IS_FRAMELESS_ICALL(opline->opcode)) {
				SET_UNUSED(opline->result);
			} else {
				/* Frameless calls usually use the return value, so always emit a free. This should be
				 * faster than checking RETURN_VALUE_USED inside the handler. */
				zend_emit_op(NULL, ZEND_FREE, op1, NULL);
			}
		} else {
			while (opline >= CG(active_op_array)->opcodes) {
				if ((opline->opcode == ZEND_FETCH_LIST_R ||
				     opline->opcode == ZEND_FETCH_LIST_W ||
				     opline->opcode == ZEND_EXT_STMT) &&
				    opline->op1_type == IS_VAR &&
				    opline->op1.var == op1->u.op.var) {
					zend_emit_op(NULL, ZEND_FREE, op1, NULL);
					return;
				}
				if (opline->result_type == IS_VAR
					&& opline->result.var == op1->u.op.var) {
					if (opline->opcode == ZEND_NEW) {
						zend_emit_op(NULL, ZEND_FREE, op1, NULL);
					}
					break;
				}
				opline--;
			}
		}
	} else if (op1->op_type == IS_CONST) {
		/* Destroy value without using GC: When opcache moves arrays into SHM it will
		 * free the zend_array structure, so references to it from outside the op array
		 * become invalid. GC would cause such a reference in the root buffer. */
		zval_ptr_dtor_nogc(&op1->u.constant);
	}
}
/* }}} */


static const char *zend_modifier_token_to_string(uint32_t token)
{
	switch (token) {
		case T_PUBLIC:
			return "public";
		case T_PROTECTED:
			return "protected";
		case T_PRIVATE:
			return "private";
		case T_STATIC:
			return "static";
		case T_FINAL:
			return "final";
		case T_READONLY:
			return "readonly";
		case T_ABSTRACT:
			return "abstract";
		case T_PUBLIC_SET:
			return "public(set)";
		case T_PROTECTED_SET:
			return "protected(set)";
		case T_PRIVATE_SET:
			return "private(set)";
		EMPTY_SWITCH_DEFAULT_CASE()
	}
}

uint32_t zend_modifier_token_to_flag(zend_modifier_target target, uint32_t token)
{
	switch (token) {
		case T_PUBLIC:
			if (target != ZEND_MODIFIER_TARGET_PROPERTY_HOOK) {
				return ZEND_ACC_PUBLIC;
			}
			break;
		case T_PROTECTED:
			if (target != ZEND_MODIFIER_TARGET_PROPERTY_HOOK) {
				return ZEND_ACC_PROTECTED;
			}
			break;
		case T_PRIVATE:
			if (target != ZEND_MODIFIER_TARGET_PROPERTY_HOOK) {
				return ZEND_ACC_PRIVATE;
			}
			break;
		case T_READONLY:
			if (target == ZEND_MODIFIER_TARGET_PROPERTY || target == ZEND_MODIFIER_TARGET_CPP) {
				return ZEND_ACC_READONLY;
			}
			break;
		case T_ABSTRACT:
			if (target == ZEND_MODIFIER_TARGET_METHOD || target == ZEND_MODIFIER_TARGET_PROPERTY) {
				return ZEND_ACC_ABSTRACT;
			}
			break;
		case T_FINAL:
			return ZEND_ACC_FINAL;
		case T_STATIC:
			if (target == ZEND_MODIFIER_TARGET_PROPERTY || target == ZEND_MODIFIER_TARGET_METHOD) {
				return ZEND_ACC_STATIC;
			}
			break;
		case T_PUBLIC_SET:
			if (target == ZEND_MODIFIER_TARGET_PROPERTY || target == ZEND_MODIFIER_TARGET_CPP) {
				return ZEND_ACC_PUBLIC_SET;
			}
			break;
		case T_PROTECTED_SET:
			if (target == ZEND_MODIFIER_TARGET_PROPERTY || target == ZEND_MODIFIER_TARGET_CPP) {
				return ZEND_ACC_PROTECTED_SET;
			}
			break;
		case T_PRIVATE_SET:
			if (target == ZEND_MODIFIER_TARGET_PROPERTY || target == ZEND_MODIFIER_TARGET_CPP) {
				return ZEND_ACC_PRIVATE_SET;
			}
			break;
	}

	char *member;
	if (target == ZEND_MODIFIER_TARGET_PROPERTY) {
		member = "property";
	} else if (target == ZEND_MODIFIER_TARGET_METHOD) {
		member = "method";
	} else if (target == ZEND_MODIFIER_TARGET_CONSTANT) {
		member = "class constant";
	} else if (target == ZEND_MODIFIER_TARGET_CPP) {
		member = "parameter";
	} else if (target == ZEND_MODIFIER_TARGET_PROPERTY_HOOK) {
		member = "property hook";
	} else {
		ZEND_UNREACHABLE();
	}

	zend_throw_exception_ex(zend_ce_compile_error, 0,
		"Cannot use the %s modifier on a %s", zend_modifier_token_to_string(token), member);
	return 0;
}

uint32_t zend_modifier_list_to_flags(zend_modifier_target target, zend_ast *modifiers)
{
	uint32_t flags = 0;
	const zend_ast_list *modifier_list = zend_ast_get_list(modifiers);

	for (uint32_t i = 0; i < modifier_list->children; i++) {
		uint32_t token = (uint32_t) Z_LVAL_P(zend_ast_get_zval(modifier_list->child[i]));
		uint32_t new_flag = zend_modifier_token_to_flag(target, token);
		if (!new_flag) {
			return 0;
		}
		/* Don't error immediately for duplicate flags, we want to prioritize the errors from zend_add_member_modifier(). */
		bool duplicate_flag = (flags & new_flag);
		flags = zend_add_member_modifier(flags, new_flag, target);
		if (!flags) {
			return 0;
		}
		if (duplicate_flag) {
			zend_throw_exception_ex(zend_ce_compile_error, 0,
				"Multiple %s modifiers are not allowed", zend_modifier_token_to_string(token));
			return 0;
		}
	}

	return flags;
}

uint32_t zend_add_class_modifier(uint32_t flags, uint32_t new_flag) /* {{{ */
{
	uint32_t new_flags = flags | new_flag;
	if ((flags & ZEND_ACC_EXPLICIT_ABSTRACT_CLASS) && (new_flag & ZEND_ACC_EXPLICIT_ABSTRACT_CLASS)) {
		zend_throw_exception(zend_ce_compile_error,
			"Multiple abstract modifiers are not allowed", 0);
		return 0;
	}
	if ((flags & ZEND_ACC_FINAL) && (new_flag & ZEND_ACC_FINAL)) {
		zend_throw_exception(zend_ce_compile_error, "Multiple final modifiers are not allowed", 0);
		return 0;
	}
	if ((flags & ZEND_ACC_READONLY_CLASS) && (new_flag & ZEND_ACC_READONLY_CLASS)) {
		zend_throw_exception(zend_ce_compile_error, "Multiple readonly modifiers are not allowed", 0);
		return 0;
	}
	if ((new_flags & ZEND_ACC_EXPLICIT_ABSTRACT_CLASS) && (new_flags & ZEND_ACC_FINAL)) {
		zend_throw_exception(zend_ce_compile_error,
			"Cannot use the final modifier on an abstract class", 0);
		return 0;
	}
	return new_flags;
}
/* }}} */

uint32_t zend_add_anonymous_class_modifier(uint32_t flags, uint32_t new_flag)
{
	uint32_t new_flags = flags | new_flag;
	if (new_flag & ZEND_ACC_EXPLICIT_ABSTRACT_CLASS) {
		zend_throw_exception(zend_ce_compile_error,
			"Cannot use the abstract modifier on an anonymous class", 0);
		return 0;
	}
	if (new_flag & ZEND_ACC_FINAL) {
		zend_throw_exception(zend_ce_compile_error, "Cannot use the final modifier on an anonymous class", 0);
		return 0;
	}
	if ((flags & ZEND_ACC_READONLY_CLASS) && (new_flag & ZEND_ACC_READONLY_CLASS)) {
		zend_throw_exception(zend_ce_compile_error, "Multiple readonly modifiers are not allowed", 0);
		return 0;
	}
	return new_flags;
}

uint32_t zend_add_member_modifier(uint32_t flags, uint32_t new_flag, zend_modifier_target target) /* {{{ */
{
	uint32_t new_flags = flags | new_flag;
	if ((flags & ZEND_ACC_PPP_MASK) && (new_flag & ZEND_ACC_PPP_MASK)) {
		zend_throw_exception(zend_ce_compile_error,
			"Multiple access type modifiers are not allowed", 0);
		return 0;
	}
	if ((new_flags & ZEND_ACC_ABSTRACT) && (new_flags & ZEND_ACC_FINAL)) {
		if (target == ZEND_MODIFIER_TARGET_METHOD) {
			zend_throw_exception(zend_ce_compile_error,
				"Cannot use the final modifier on an abstract method", 0);
			return 0;
		}
		if (target == ZEND_MODIFIER_TARGET_PROPERTY) {
			zend_throw_exception(zend_ce_compile_error,
				"Cannot use the final modifier on an abstract property", 0);
			return 0;
		}
	}
	if (target == ZEND_MODIFIER_TARGET_PROPERTY || target == ZEND_MODIFIER_TARGET_CPP) {
		if ((flags & ZEND_ACC_PPP_SET_MASK) && (new_flag & ZEND_ACC_PPP_SET_MASK)) {
			zend_throw_exception(zend_ce_compile_error,
				"Multiple access type modifiers are not allowed", 0);
			return 0;
		}
	}
	return new_flags;
}
/* }}} */

ZEND_API zend_string *zend_create_member_string(const zend_string *class_name, const zend_string *member_name) {
	return zend_string_concat3(
		ZSTR_VAL(class_name), ZSTR_LEN(class_name),
		"::", sizeof("::") - 1,
		ZSTR_VAL(member_name), ZSTR_LEN(member_name));
}

static zend_string *zend_concat_names(const char *name1, size_t name1_len, const char *name2, size_t name2_len) {
	return zend_string_concat3(name1, name1_len, "\\", 1, name2, name2_len);
}

static zend_string *zend_prefix_with_ns(zend_string *name) {
	if (FC(current_namespace)) {
		const zend_string *ns = FC(current_namespace);
		return zend_concat_names(ZSTR_VAL(ns), ZSTR_LEN(ns), ZSTR_VAL(name), ZSTR_LEN(name));
	} else {
		return zend_string_copy(name);
	}
}

static zend_string *zend_resolve_non_class_name(
	zend_string *name, uint32_t type, bool *is_fully_qualified,
	bool case_sensitive, const HashTable *current_import_sub
) {
	const char *compound;
	*is_fully_qualified = false;

	if (ZSTR_VAL(name)[0] == '\\') {
		/* Remove \ prefix (only relevant if this is a string rather than a label) */
		*is_fully_qualified = true;
		return zend_string_init(ZSTR_VAL(name) + 1, ZSTR_LEN(name) - 1, 0);
	}

	if (type == ZEND_NAME_FQ) {
		*is_fully_qualified = true;
		return zend_string_copy(name);
	}

	if (type == ZEND_NAME_RELATIVE) {
		*is_fully_qualified = true;
		return zend_prefix_with_ns(name);
	}

	if (current_import_sub) {
		/* If an unqualified name is a function/const alias, replace it. */
		zend_string *import_name;
		if (case_sensitive) {
			import_name = zend_hash_find_ptr(current_import_sub, name);
		} else {
			import_name = zend_hash_find_ptr_lc(current_import_sub, name);
		}

		if (import_name) {
			*is_fully_qualified = true;
			return zend_string_copy(import_name);
		}
	}

	compound = memchr(ZSTR_VAL(name), '\\', ZSTR_LEN(name));
	if (compound) {
		*is_fully_qualified = true;
	}

	if (compound && FC(imports)) {
		/* If the first part of a qualified name is an alias, substitute it. */
		size_t len = compound - ZSTR_VAL(name);
		const zend_string *import_name = zend_hash_str_find_ptr_lc(FC(imports), ZSTR_VAL(name), len);

		if (import_name) {
			return zend_concat_names(
				ZSTR_VAL(import_name), ZSTR_LEN(import_name), ZSTR_VAL(name) + len + 1, ZSTR_LEN(name) - len - 1);
		}
	}

	return zend_prefix_with_ns(name);
}
/* }}} */

static zend_string *zend_resolve_function_name(zend_string *name, uint32_t type, bool *is_fully_qualified)
{
	return zend_resolve_non_class_name(
		name, type, is_fully_qualified, false, FC(imports_function));
}

static zend_string *zend_resolve_const_name(zend_string *name, uint32_t type, bool *is_fully_qualified)
{
	return zend_resolve_non_class_name(
		name, type, is_fully_qualified, true, FC(imports_const));
}

static zend_string *zend_resolve_class_name(zend_string *name, uint32_t type) /* {{{ */
{
	const char *compound;

	if (ZEND_FETCH_CLASS_DEFAULT != zend_get_class_fetch_type(name)) {
		if (type == ZEND_NAME_FQ) {
			zend_error_noreturn(E_COMPILE_ERROR,
				"'\\%s' is an invalid class name", ZSTR_VAL(name));
		}
		if (type == ZEND_NAME_RELATIVE) {
			zend_error_noreturn(E_COMPILE_ERROR,
				"'namespace\\%s' is an invalid class name", ZSTR_VAL(name));
		}
		ZEND_ASSERT(type == ZEND_NAME_NOT_FQ);
		return zend_string_copy(name);
	}

	if (type == ZEND_NAME_RELATIVE) {
		return zend_prefix_with_ns(name);
	}

	if (type == ZEND_NAME_FQ) {
		if (ZSTR_VAL(name)[0] == '\\') {
			/* Remove \ prefix (only relevant if this is a string rather than a label) */
			name = zend_string_init(ZSTR_VAL(name) + 1, ZSTR_LEN(name) - 1, 0);
			if (ZEND_FETCH_CLASS_DEFAULT != zend_get_class_fetch_type(name)) {
				zend_error_noreturn(E_COMPILE_ERROR,
					"'\\%s' is an invalid class name", ZSTR_VAL(name));
			}
			return name;
		}

		return zend_string_copy(name);
	}

	if (FC(imports)) {
		compound = memchr(ZSTR_VAL(name), '\\', ZSTR_LEN(name));
		if (compound) {
			/* If the first part of a qualified name is an alias, substitute it. */
			size_t len = compound - ZSTR_VAL(name);
			const zend_string *import_name =
				zend_hash_str_find_ptr_lc(FC(imports), ZSTR_VAL(name), len);

			if (import_name) {
				return zend_concat_names(
					ZSTR_VAL(import_name), ZSTR_LEN(import_name), ZSTR_VAL(name) + len + 1, ZSTR_LEN(name) - len - 1);
			}
		} else {
			/* If an unqualified name is an alias, replace it. */
			zend_string *import_name
				= zend_hash_find_ptr_lc(FC(imports), name);

			if (import_name) {
				return zend_string_copy(import_name);
			}
		}
	}

	/* If not fully qualified and not an alias, prepend the current namespace */
	return zend_prefix_with_ns(name);
}
/* }}} */

static zend_string *zend_resolve_class_name_ast(zend_ast *ast) /* {{{ */
{
	const zval *class_name = zend_ast_get_zval(ast);
	if (Z_TYPE_P(class_name) != IS_STRING) {
		zend_error_noreturn(E_COMPILE_ERROR, "Illegal class name");
	}
	return zend_resolve_class_name(Z_STR_P(class_name), ast->attr);
}
/* }}} */

static void label_ptr_dtor(zval *zv) /* {{{ */
{
	efree_size(Z_PTR_P(zv), sizeof(zend_label));
}
/* }}} */

static void str_dtor(zval *zv)  /* {{{ */ {
	zend_string_release_ex(Z_STR_P(zv), 0);
}
/* }}} */

static uint32_t zend_add_try_element(uint32_t try_op) /* {{{ */
{
	zend_op_array *op_array = CG(active_op_array);
	uint32_t try_catch_offset = op_array->last_try_catch++;
	zend_try_catch_element *elem;

	op_array->try_catch_array = safe_erealloc(
		op_array->try_catch_array, sizeof(zend_try_catch_element), op_array->last_try_catch, 0);

	elem = &op_array->try_catch_array[try_catch_offset];
	elem->try_op = try_op;
	elem->catch_op = 0;
	elem->finally_op = 0;
	elem->finally_end = 0;

	return try_catch_offset;
}
/* }}} */

ZEND_API void function_add_ref(zend_function *function) /* {{{ */
{
	if (function->type == ZEND_USER_FUNCTION) {
		zend_op_array *op_array = &function->op_array;
		if (op_array->refcount) {
			(*op_array->refcount)++;
		}

		ZEND_MAP_PTR_INIT(op_array->run_time_cache, NULL);
		ZEND_MAP_PTR_INIT(op_array->static_variables_ptr, NULL);
	}

	if (function->common.function_name) {
		zend_string_addref(function->common.function_name);
	}
}
/* }}} */

static zend_never_inline ZEND_COLD ZEND_NORETURN void do_bind_function_error(const zend_string *lcname, const zend_op_array *op_array, bool compile_time) /* {{{ */
{
	const zval *zv = zend_hash_find_known_hash(compile_time ? CG(function_table) : EG(function_table), lcname);
	int error_level = compile_time ? E_COMPILE_ERROR : E_ERROR;
	const zend_function *old_function;

	ZEND_ASSERT(zv != NULL);
	old_function = Z_PTR_P(zv);
	if (old_function->type == ZEND_USER_FUNCTION
		&& old_function->op_array.last > 0) {
		zend_error_noreturn(error_level, "Cannot redeclare function %s() (previously declared in %s:%d)",
					op_array ? ZSTR_VAL(op_array->function_name) : ZSTR_VAL(old_function->common.function_name),
					ZSTR_VAL(old_function->op_array.filename),
					old_function->op_array.line_start);
	} else {
		zend_error_noreturn(error_level, "Cannot redeclare function %s()",
			op_array ? ZSTR_VAL(op_array->function_name) : ZSTR_VAL(old_function->common.function_name));
	}
}

ZEND_API zend_result do_bind_function(zend_function *func, const zval *lcname) /* {{{ */
{
	zend_function *added_func = zend_hash_add_ptr(EG(function_table), Z_STR_P(lcname), func);
	if (UNEXPECTED(!added_func)) {
		do_bind_function_error(Z_STR_P(lcname), &func->op_array, false);
		return FAILURE;
	}

	if (func->op_array.refcount) {
		++*func->op_array.refcount;
	}
	if (func->common.function_name) {
		zend_string_addref(func->common.function_name);
	}
	zend_observer_function_declared_notify(&func->op_array, Z_STR_P(lcname));
	return SUCCESS;
}
/* }}} */

ZEND_API zend_class_entry *zend_bind_class_in_slot(
		zval *class_table_slot, const zval *lcname, zend_string *lc_parent_name)
{
	zend_class_entry *ce = Z_PTR_P(class_table_slot);
	bool is_preloaded =
		(ce->ce_flags & ZEND_ACC_PRELOADED) && !(CG(compiler_options) & ZEND_COMPILE_PRELOAD);
	bool success;
	if (EXPECTED(!is_preloaded)) {
		success = zend_hash_set_bucket_key(EG(class_table), (Bucket*) class_table_slot, Z_STR_P(lcname)) != NULL;
	} else {
		/* If preloading is used, don't replace the existing bucket, add a new one. */
		success = zend_hash_add_ptr(EG(class_table), Z_STR_P(lcname), ce) != NULL;
	}
	if (UNEXPECTED(!success)) {
		zend_class_entry *old_class = zend_hash_find_ptr(EG(class_table), Z_STR_P(lcname));
		ZEND_ASSERT(old_class);
		zend_class_redeclaration_error(E_COMPILE_ERROR, old_class);
		return NULL;
	}

	if (ce->ce_flags & ZEND_ACC_LINKED) {
		zend_observer_class_linked_notify(ce, Z_STR_P(lcname));
		return ce;
	}

	ce = zend_do_link_class(ce, lc_parent_name, Z_STR_P(lcname));
	if (ce) {
		zend_observer_class_linked_notify(ce, Z_STR_P(lcname));
		return ce;
	}

	if (!is_preloaded) {
		/* Reload bucket pointer, the hash table may have been reallocated */
		zval *zv = zend_hash_find(EG(class_table), Z_STR_P(lcname));
		zend_hash_set_bucket_key(EG(class_table), (Bucket *) zv, Z_STR_P(lcname + 1));
	} else {
		zend_hash_del(EG(class_table), Z_STR_P(lcname));
	}
	return NULL;
}

ZEND_API zend_result do_bind_class(zval *lcname, zend_string *lc_parent_name) /* {{{ */
{
	zval *rtd_key, *zv;

	rtd_key = lcname + 1;

	zv = zend_hash_find_known_hash(EG(class_table), Z_STR_P(rtd_key));

	if (UNEXPECTED(!zv)) {
		const zend_class_entry *ce = zend_hash_find_ptr(EG(class_table), Z_STR_P(lcname));
		ZEND_ASSERT(ce);
		zend_class_redeclaration_error(E_COMPILE_ERROR, ce);
		return FAILURE;
	}

	/* Register the derived class */
	return zend_bind_class_in_slot(zv, lcname, lc_parent_name) ? SUCCESS : FAILURE;
}
/* }}} */

static zend_string *add_type_string(zend_string *type, zend_string *new_type, bool is_intersection) {
	zend_string *result;
	if (type == NULL) {
		return zend_string_copy(new_type);
	}

	if (is_intersection) {
		result = zend_string_concat3(ZSTR_VAL(type), ZSTR_LEN(type),
			"&", 1, ZSTR_VAL(new_type), ZSTR_LEN(new_type));
		zend_string_release(type);
	} else {
		result = zend_string_concat3(
			ZSTR_VAL(type), ZSTR_LEN(type), "|", 1, ZSTR_VAL(new_type), ZSTR_LEN(new_type));
		zend_string_release(type);
	}
	return result;
}

static zend_string *resolve_class_name(zend_string *name, const zend_class_entry *scope) {
	if (scope) {
		if (zend_string_equals_ci(name, ZSTR_KNOWN(ZEND_STR_SELF))) {
			name = scope->name;
		} else if (zend_string_equals_ci(name, ZSTR_KNOWN(ZEND_STR_PARENT)) && scope->parent) {
			name = scope->parent->name;
		}
	}

	/* The resolved name for anonymous classes contains null bytes. Cut off everything after the
	 * null byte here, to avoid larger parts of the type being omitted by printing code later. */
	size_t len = strlen(ZSTR_VAL(name));
	if (len != ZSTR_LEN(name)) {
		return zend_string_init(ZSTR_VAL(name), len, 0);
	}
	return zend_string_copy(name);
}

static zend_string *add_intersection_type(zend_string *str,
	const zend_type_list *intersection_type_list,
	bool is_bracketed)
{
	const zend_type *single_type;
	zend_string *intersection_str = NULL;

	ZEND_TYPE_LIST_FOREACH(intersection_type_list, single_type) {
		ZEND_ASSERT(!ZEND_TYPE_HAS_LIST(*single_type));
		ZEND_ASSERT(ZEND_TYPE_HAS_NAME(*single_type));

		intersection_str = add_type_string(intersection_str, ZEND_TYPE_NAME(*single_type), /* is_intersection */ true);
	} ZEND_TYPE_LIST_FOREACH_END();

	ZEND_ASSERT(intersection_str);

	if (is_bracketed) {
		zend_string *result = zend_string_concat3("(", 1, ZSTR_VAL(intersection_str), ZSTR_LEN(intersection_str), ")", 1);
		zend_string_release(intersection_str);
		intersection_str = result;
	}
	str = add_type_string(str, intersection_str, /* is_intersection */ false);
	zend_string_release(intersection_str);
	return str;
}

zend_string *zend_type_to_string_resolved(const zend_type type, const zend_class_entry *scope) {
	zend_string *str = NULL;

	/* Pure intersection type */
	if (ZEND_TYPE_IS_INTERSECTION(type)) {
		ZEND_ASSERT(!ZEND_TYPE_IS_UNION(type));
		str = add_intersection_type(str, ZEND_TYPE_LIST(type), /* is_bracketed */ false);
	} else if (ZEND_TYPE_HAS_LIST(type)) {
		/* A union type might not be a list */
		const zend_type *list_type;
		ZEND_TYPE_LIST_FOREACH(ZEND_TYPE_LIST(type), list_type) {
			if (ZEND_TYPE_IS_INTERSECTION(*list_type)) {
				str = add_intersection_type(str, ZEND_TYPE_LIST(*list_type), /* is_bracketed */ true);
				continue;
			}
			ZEND_ASSERT(!ZEND_TYPE_HAS_LIST(*list_type));
			ZEND_ASSERT(ZEND_TYPE_HAS_NAME(*list_type));

			zend_string *name = ZEND_TYPE_NAME(*list_type);
			zend_string *resolved = resolve_class_name(name, scope);
			str = add_type_string(str, resolved, /* is_intersection */ false);
			zend_string_release(resolved);
		} ZEND_TYPE_LIST_FOREACH_END();
	} else if (ZEND_TYPE_HAS_NAME(type)) {
		str = resolve_class_name(ZEND_TYPE_NAME(type), scope);
	}

	uint32_t type_mask = ZEND_TYPE_PURE_MASK(type);

	if (type_mask == MAY_BE_ANY) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_MIXED), /* is_intersection */ false);

		return str;
	}
	if (type_mask & MAY_BE_STATIC) {
		zend_string *name = ZSTR_KNOWN(ZEND_STR_STATIC);
		// During compilation of eval'd code the called scope refers to the scope calling the eval
		if (scope && !zend_is_compiling()) {
			const zend_class_entry *called_scope = zend_get_called_scope(EG(current_execute_data));
			if (called_scope) {
				name = called_scope->name;
			}
		}
		str = add_type_string(str, name, /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_CALLABLE) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_CALLABLE), /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_OBJECT) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_OBJECT), /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_ARRAY) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_ARRAY), /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_STRING) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_STRING), /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_LONG) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_INT), /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_DOUBLE) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_FLOAT), /* is_intersection */ false);
	}
	if ((type_mask & MAY_BE_BOOL) == MAY_BE_BOOL) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_BOOL), /* is_intersection */ false);
	} else if (type_mask & MAY_BE_FALSE) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_FALSE), /* is_intersection */ false);
	} else if (type_mask & MAY_BE_TRUE) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_TRUE), /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_VOID) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_VOID), /* is_intersection */ false);
	}
	if (type_mask & MAY_BE_NEVER) {
		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_NEVER), /* is_intersection */ false);
	}

	if (type_mask & MAY_BE_NULL) {
		bool is_union = !str || memchr(ZSTR_VAL(str), '|', ZSTR_LEN(str)) != NULL;
		bool has_intersection = !str || memchr(ZSTR_VAL(str), '&', ZSTR_LEN(str)) != NULL;
		if (!is_union && !has_intersection) {
			zend_string *nullable_str = zend_string_concat2("?", 1, ZSTR_VAL(str), ZSTR_LEN(str));
			zend_string_release(str);
			return nullable_str;
		}

		str = add_type_string(str, ZSTR_KNOWN(ZEND_STR_NULL_LOWERCASE), /* is_intersection */ false);
	}
	return str;
}

ZEND_API zend_string *zend_type_to_string(zend_type type) {
	return zend_type_to_string_resolved(type, NULL);
}

static bool is_generator_compatible_class_type(const zend_string *name) {
	return zend_string_equals_ci(name, ZSTR_KNOWN(ZEND_STR_TRAVERSABLE))
		|| zend_string_equals_literal_ci(name, "Iterator")
		|| zend_string_equals_literal_ci(name, "Generator");
}

static void zend_mark_function_as_generator(void) /* {{{ */
{
	if (!CG(active_op_array)->function_name) {
		zend_error_noreturn(E_COMPILE_ERROR,
			"The \"yield\" expression can only be used inside a function");
	}

	if (CG(active_op_array)->fn_flags & ZEND_ACC_HAS_RETURN_TYPE) {
		const zend_type return_type = CG(active_op_array)->arg_info[-1].type;
		bool valid_type = (ZEND_TYPE_FULL_MASK(return_type) & MAY_BE_OBJECT) != 0;
		if (!valid_type) {
			const zend_type *single_type;
			ZEND_TYPE_FOREACH(return_type, single_type) {
				if (ZEND_TYPE_HAS_NAME(*single_type)
						&& is_generator_compatible_class_type(ZEND_TYPE_NAME(*single_type))) {
					valid_type = true;
					break;
				}
			} ZEND_TYPE_FOREACH_END();
		}

		if (!valid_type) {
			zend_string *str = zend_type_to_string(return_type);
			zend_error_noreturn(E_COMPILE_ERROR,
				"Generator return type must be a supertype of Generator, %s given",
				ZSTR_VAL(str));
		}
	}

	CG(active_op_array)->fn_flags |= ZEND_ACC_GENERATOR;
}
/* }}} */

ZEND_API zend_string *zend_mangle_property_name(const char *src1, size_t src1_length, const char *src2, size_t src2_length, bool internal) /* {{{ */
{
	size_t prop_name_length = 1 + src1_length + 1 + src2_length;
	zend_string *prop_name = zend_string_alloc(prop_name_length, internal);

	ZSTR_VAL(prop_name)[0] = '\0';
	memcpy(ZSTR_VAL(prop_name) + 1, src1, src1_length+1);
	memcpy(ZSTR_VAL(prop_name) + 1 + src1_length + 1, src2, src2_length+1);
	return prop_name;
}
/* }}} */

ZEND_API zend_result zend_unmangle_property_name_ex(const zend_string *name, const char **class_name, const char **prop_name, size_t *prop_len) /* {{{ */
{
	size_t class_name_len;
	size_t anonclass_src_len;

	*class_name = NULL;

	if (!ZSTR_LEN(name) || ZSTR_VAL(name)[0] != '\0') {
		*prop_name = ZSTR_VAL(name);
		if (prop_len) {
			*prop_len = ZSTR_LEN(name);
		}
		return SUCCESS;
	}
	if (ZSTR_LEN(name) < 3 || ZSTR_VAL(name)[1] == '\0') {
		zend_error(E_NOTICE, "Illegal member variable name");
		*prop_name = ZSTR_VAL(name);
		if (prop_len) {
			*prop_len = ZSTR_LEN(name);
		}
		return FAILURE;
	}

	class_name_len = zend_strnlen(ZSTR_VAL(name) + 1, ZSTR_LEN(name) - 2);
	if (class_name_len >= ZSTR_LEN(name) - 2 || ZSTR_VAL(name)[class_name_len + 1] != '\0') {
		zend_error(E_NOTICE, "Corrupt member variable name");
		*prop_name = ZSTR_VAL(name);
		if (prop_len) {
			*prop_len = ZSTR_LEN(name);
		}
		return FAILURE;
	}

	*class_name = ZSTR_VAL(name) + 1;
	anonclass_src_len = zend_strnlen(*class_name + class_name_len + 1, ZSTR_LEN(name) - class_name_len - 2);
	if (class_name_len + anonclass_src_len + 2 != ZSTR_LEN(name)) {
		class_name_len += anonclass_src_len + 1;
	}
	*prop_name = ZSTR_VAL(name) + class_name_len + 2;
	if (prop_len) {
		*prop_len = ZSTR_LEN(name) - class_name_len - 2;
	}
	return SUCCESS;
}
/* }}} */

static bool array_is_const_ex(const zend_array *array, uint32_t *max_checks)
{
	if (zend_hash_num_elements(array) > *max_checks) {
		return false;
	}
	*max_checks -= zend_hash_num_elements(array);

	zval *element;
	ZEND_HASH_FOREACH_VAL(array, element) {
		if (Z_TYPE_P(element) < IS_ARRAY) {
			continue;
		} else if (Z_TYPE_P(element) == IS_ARRAY) {
			if (!array_is_const_ex(array, max_checks)) {
				return false;
			}
		} else {
			return false;
		}
	} ZEND_HASH_FOREACH_END();

	return true;
}

static bool array_is_const(const zend_array *array)
{
	uint32_t max_checks = 50;
	return array_is_const_ex(array, &max_checks);
}

static bool can_ct_eval_const(const zend_constant *c) {
	if (ZEND_CONSTANT_FLAGS(c) & CONST_DEPRECATED) {
		return 0;
	}
	if ((ZEND_CONSTANT_FLAGS(c) & CONST_PERSISTENT)
			&& !(CG(compiler_options) & ZEND_COMPILE_NO_PERSISTENT_CONSTANT_SUBSTITUTION)
			&& !((ZEND_CONSTANT_FLAGS(c) & CONST_NO_FILE_CACHE)
				&& (CG(compiler_options) & ZEND_COMPILE_WITH_FILE_CACHE))) {
		return 1;
	}
	if (Z_TYPE(c->value) < IS_ARRAY
			&& !(CG(compiler_options) & ZEND_COMPILE_NO_CONSTANT_SUBSTITUTION)) {
		return 1;
	} else if (Z_TYPE(c->value) == IS_ARRAY
			&& !(CG(compiler_options) & ZEND_COMPILE_NO_CONSTANT_SUBSTITUTION)
			&& array_is_const(Z_ARR(c->value))) {
		return 1;
	}
	return 0;
}

static bool zend_try_ct_eval_const(zval *zv, zend_string *name, bool is_fully_qualified) /* {{{ */
{
	/* Substitute true, false and null (including unqualified usage in namespaces)
	 * before looking up the possibly namespaced name. */
	const char *lookup_name = ZSTR_VAL(name);
	size_t lookup_len = ZSTR_LEN(name);

	if (!is_fully_qualified) {
		zend_get_unqualified_name(name, &lookup_name, &lookup_len);
	}

	zend_constant *c;
	if ((c = zend_get_special_const(lookup_name, lookup_len))) {
		ZVAL_COPY_VALUE(zv, &c->value);
		return 1;
	}
	c = zend_hash_find_ptr(EG(zend_constants), name);
	if (c && can_ct_eval_const(c)) {
		ZVAL_COPY_OR_DUP(zv, &c->value);
		return 1;
	}
	return 0;
}
/* }}} */

static inline bool zend_is_scope_known(void) /* {{{ */
{
	if (!CG(active_op_array)) {
		/* This can only happen when evaluating a default value string. */
		return 0;
	}

	if (CG(active_op_array)->fn_flags & ZEND_ACC_CLOSURE) {
		/* Closures can be rebound to a different scope */
		return 0;
	}

	if (!CG(active_class_entry)) {
		/* The scope is known if we're in a free function (no scope), but not if we're in
		 * a file/eval (which inherits including/eval'ing scope). */
		return CG(active_op_array)->function_name != NULL;
	}

	/* For traits self etc refers to the using class, not the trait itself */
	return (CG(active_class_entry)->ce_flags & ZEND_ACC_TRAIT) == 0;
}
/* }}} */

static inline bool class_name_refers_to_active_ce(const zend_string *class_name, uint32_t fetch_type) /* {{{ */
{
	if (!CG(active_class_entry)) {
		return 0;
	}
	if (fetch_type == ZEND_FETCH_CLASS_SELF && zend_is_scope_known()) {
		return 1;
	}
	return fetch_type == ZEND_FETCH_CLASS_DEFAULT
		&& zend_string_equals_ci(class_name, CG(active_class_entry)->name);
}
/* }}} */

uint32_t zend_get_class_fetch_type(const zend_string *name) /* {{{ */
{
	if (zend_string_equals_ci(name, ZSTR_KNOWN(ZEND_STR_SELF))) {
		return ZEND_FETCH_CLASS_SELF;
	} else if (zend_string_equals_ci(name, ZSTR_KNOWN(ZEND_STR_PARENT))) {
		return ZEND_FETCH_CLASS_PARENT;
	} else if (zend_string_equals_ci(name, ZSTR_KNOWN(ZEND_STR_STATIC))) {
		return ZEND_FETCH_CLASS_STATIC;
	} else {
		return ZEND_FETCH_CLASS_DEFAULT;
	}
}
/* }}} */

static uint32_t zend_get_class_fetch_type_ast(zend_ast *name_ast) /* {{{ */
{
	/* Fully qualified names are always default refs */
	if (name_ast->attr == ZEND_NAME_FQ) {
		return ZEND_FETCH_CLASS_DEFAULT;
	}

	return zend_get_class_fetch_type(zend_ast_get_str(name_ast));
}
/* }}} */

static zend_string *zend_resolve_const_class_name_reference(zend_ast *ast, const char *type)
{
	zend_string *class_name = zend_ast_get_str(ast);
	if (ZEND_FETCH_CLASS_DEFAULT != zend_get_class_fetch_type_ast(ast)) {
		zend_error_noreturn(E_COMPILE_ERROR,
			"Cannot use \"%s\" as %s, as it is reserved",
			ZSTR_VAL(class_name), type);
	}
	return zend_resolve_class_name(class_name, ast->attr);
}

static void zend_ensure_valid_class_fetch_type(uint32_t fetch_type) /* {{{ */
{
	if (fetch_type != ZEND_FETCH_CLASS_DEFAULT && zend_is_scope_known()) {
		zend_class_entry *ce = CG(active_class_entry);
		if (!ce) {
			zend_error_noreturn(E_COMPILE_ERROR, "Cannot use \"%s\" when no class scope is active",
				fetch_type == ZEND_FETCH_CLASS_SELF ? "self" :
				fetch_type == ZEND_FETCH_CLASS_PARENT ? "parent" : "static");
		} else if (fetch_type == ZEND_FETCH_CLASS_PARENT && !ce->parent_name) {
			zend_error_noreturn(E_COMPILE_ERROR,
				"Cannot use \"parent\" when current class scope has no parent");
		}
	}
}
/* }}} */

static bool zend_try_compile_const_expr_resolve_class_name(zval *zv, zend_ast *class_ast) /* {{{ */
{
	uint32_t fetch_type;
	const zval *class_name;

	if (class_ast->kind != ZEND_AST_ZVAL) {
		return 0;
	}

	class_name = zend_ast_get_zval(class_ast);

	if (Z_TYPE_P(class_name) != IS_STRING) {
		zend_error_noreturn(E_COMPILE_ERROR, "Illegal class name");
	}

	fetch_type = zend_get_class_fetch_type(Z_STR_P(class_name));
	zend_ensure_valid_class_fetch_type(fetch_type);

	switch (fetch_type) {
		case ZEND_FETCH_CLASS_SELF:
			if (CG(active_class_entry) && zend_is_scope_known()) {
				ZVAL_STR_COPY(zv, CG(active_class_entry)->name);
				return 1;
			}
			return 0;
		case ZEND_FETCH_CLASS_PARENT:
			if (CG(active_class_entry) && CG(active_class_entry)->parent_name
					&& zend_is_scope_known()) {
				ZVAL_STR_COPY(zv, CG(active_class_entry)->parent_name);
				return 1;
			}
			return 0;
		case ZEND_FETCH_CLASS_STATIC:
			return 0;
		case ZEND_FETCH_CLASS_DEFAULT:
			ZVAL_STR(zv, zend_resolve_class_name_ast(class_ast));
			return 1;
		EMPTY_SWITCH_DEFAULT_CASE()
	}
}
/* }}} */

/* We don't use zend_verify_const_access because we need to deal with unlinked classes. */
static bool zend_verify_ct_const_access(const zend_class_constant *c, const zend_class_entry *scope)
{
	if (ZEND_CLASS_CONST_FLAGS(c) & ZEND_ACC_DEPRECATED) {
		return 0;
	} else if (c->ce->ce_flags & ZEND_ACC_TRAIT) {
		/* This condition is only met on directly accessing trait constants,
		 * because the ce is replaced to the class entry of the composing class
		 * on binding. */
		return 0;
	} else if (ZEND_CLASS_CONST_FLAGS(c) & ZEND_ACC_PUBLIC) {
		return 1;
	} else if (ZEND_CLASS_CONST_FLAGS(c) & ZEND_ACC_PRIVATE) {
		return c->ce == scope;
	} else {
		zend_class_entry *ce = c->ce;
		while (1) {
			if (ce == scope) {
				return 1;
			}
			if (!ce->parent) {
				break;
			}
			if (ce->ce_flags & ZEND_ACC_RESOLVED_PARENT) {
				ce = ce->parent;
			} else {
				ce = zend_hash_find_ptr_lc(CG(class_table), ce->parent_name);
				if (!ce) {
					break;
				}
			}
		}
		/* Reverse case cannot be true during compilation */
		return 0;
	}
}

static bool zend_try_ct_eval_class_const(zval *zv, zend_string *class_name, zend_string *name) /* {{{ */
{
	uint32_t fetch_type = zend_get_class_fetch_type(class_name);
	zend_class_constant *cc;
	zval *c;

	if (class_name_refers_to_active_ce(class_name, fetch_type)) {
		cc = zend_hash_find_ptr(&CG(active_class_entry)->constants_table, name);
	} else if (fetch_type == ZEND_FETCH_CLASS_DEFAULT && !(CG(compiler_options) & ZEND_COMPILE_NO_CONSTANT_SUBSTITUTION)) {
		const zend_class_entry *ce = zend_hash_find_ptr_lc(CG(class_table), class_name);
		if (ce) {
			cc = zend_hash_find_ptr(&ce->constants_table, name);
		} else {
			return 0;
		}
	} else {
		return 0;
	}

	if (CG(compiler_options) & ZEND_COMPILE_NO_PERSISTENT_CONSTANT_SUBSTITUTION) {
		return 0;
	}

	if (!cc || !zend_verify_ct_const_access(cc, CG(active_class_entry))) {
		return 0;
	}

	c = &cc->value;

	/* Substitute case-sensitive (or lowercase) persistent class constants */
	if (Z_TYPE_P(c) < IS_ARRAY) {
		ZVAL_COPY_OR_DUP(zv, c);
		return 1;
	} else if (Z_TYPE_P(c) == IS_ARRAY && array_is_const(Z_ARR_P(c))) {
		ZVAL_COPY_OR_DUP(zv, c);
		return 1;
	}

	return 0;
}
/* }}} */

static void zend_add_to_list(void *result, void *item) /* {{{ */
{
	void** list = *(void**)result;
	size_t n = 0;

	if (list) {
		while (list[n]) {
			n++;
		}
	}

	list = erealloc(list, sizeof(void*) * (n+2));

	list[n]   = item;
	list[n+1] = NULL;

	*(void**)result = list;
}
/* }}} */

static void zend_do_extended_stmt(znode* result) /* {{{ */
{
	zend_op *opline;

	if (!(CG(compiler_options) & ZEND_COMPILE_EXTENDED_STMT)) {
		return;
	}

	opline = get_next_op();

	opline->opcode = ZEND_EXT_STMT;
	if (result) {
		if (result->op_type == IS_CONST) {
			Z_TRY_ADDREF(result->u.constant);
		}
		SET_NODE(opline->op1, result);
	}
}
/* }}} */

static void zend_do_extended_fcall_begin(void) /* {{{ */
{
	zend_op *opline;

	if (!(CG(compiler_options) & ZEND_COMPILE_EXTENDED_FCALL)) {
		return;
	}

	opline = get_next_op();

	opline->opcode = ZEND_EXT_FCALL_BEGIN;
}
/* }}} */

static void zend_do_extended_fcall_end(void) /* {{{ */
{
	zend_op *opline;

	if (!(CG(compiler_options) & ZEND_COMPILE_EXTENDED_FCALL)) {
		return;
	}

	opline = get_next_op();

	opline->opcode = ZEND_EXT_FCALL_END;
}
/* }}} */

ZEND_API bool zend_is_auto_global_str(const char *name, size_t len) /* {{{ */ {
	zend_auto_global *auto_global;

	if ((auto_global = zend_hash_str_find_ptr(CG(auto_globals), name, len)) != NULL) {
		if (auto_global->armed) {
			auto_global->armed = auto_global->auto_global_callback(auto_global->name);
		}
		return 1;
	}
	return 0;
}
/* }}} */

ZEND_API bool zend_is_auto_global(zend_string *name) /* {{{ */
{
	zend_auto_global *auto_global;

	if ((auto_global = zend_hash_find_ptr(CG(auto_globals), name)) != NULL) {
		if (auto_global->armed) {
			auto_global->armed = auto_global->auto_global_callback(auto_global->name);
		}
		return 1;
	}
	return 0;
}
/* }}} */

ZEND_API zend_result zend_register_auto_global(zend_string *name, bool jit, zend_auto_global_callback auto_global_callback) /* {{{ */
{
	zend_auto_global auto_global;
	zend_result retval;

	auto_global.name = name;
	auto_global.auto_global_callback = auto_global_callback;
	auto_global.jit = jit;

	retval = zend_hash_add_mem(CG(auto_globals), auto_global.name, &auto_global, sizeof(zend_auto_global)) != NULL ? SUCCESS : FAILURE;

	return retval;
}
/* }}} */

ZEND_API void zend_activate_auto_globals(void) /* {{{ */
{
	zend_auto_global *auto_global;

	ZEND_HASH_MAP_FOREACH_PTR(CG(auto_globals), auto_global) {
		auto_global->armed = auto_global->jit || auto_global->auto_global_callback;
	} ZEND_HASH_FOREACH_END();

	ZEND_HASH_MAP_FOREACH_PTR(CG(auto_globals), auto_global) {
		if (auto_global->armed && !auto_global->jit) {
			auto_global->armed = auto_global->auto_global_callback(auto_global->name);
		}
	} ZEND_HASH_FOREACH_END();
}
/* }}} */

int ZEND_FASTCALL zendlex(zend_parser_stack_elem *elem) /* {{{ */
{
	zval zv;
	int ret;

	if (CG(increment_lineno)) {
		CG(zend_lineno)++;
		CG(increment_lineno) = 0;
	}

	ret = lex_scan(&zv, elem);
	ZEND_ASSERT(!EG(exception) || ret == T_ERROR);
	return ret;

}
/* }}} */

ZEND_API void zend_initialize_class_data(zend_class_entry *ce, bool nullify_handlers) /* {{{ */
{
	bool persistent_hashes = ce->type == ZEND_INTERNAL_CLASS;

	ce->refcount = 1;
	ce->ce_flags = ZEND_ACC_CONSTANTS_UPDATED;
	ce->ce_flags2 = 0;

	if (CG(compiler_options) & ZEND_COMPILE_GUARDS) {
		ce->ce_flags |= ZEND_ACC_USE_GUARDS;
	}

	ce->default_properties_table = NULL;
	ce->default_static_members_table = NULL;
	zend_hash_init(&ce->properties_info, 8, NULL, NULL, persistent_hashes);
	zend_hash_init(&ce->constants_table, 8, NULL, NULL, persistent_hashes);
	zend_hash_init(&ce->function_table, 8, NULL, ZEND_FUNCTION_DTOR, persistent_hashes);

	ce->doc_comment = NULL;

	ZEND_MAP_PTR_INIT(ce->static_members_table, NULL);
	ZEND_MAP_PTR_INIT(ce->mutable_data, NULL);

	ce->default_object_handlers = &std_object_handlers;
	ce->default_properties_count = 0;
	ce->default_static_members_count = 0;
	ce->properties_info_table = NULL;
	ce->attributes = NULL;
	ce->enum_backing_type = IS_UNDEF;
	ce->backed_enum_table = NULL;

	if (nullify_handlers) {
		ce->constructor = NULL;
		ce->destructor = NULL;
		ce->clone = NULL;
		ce->__get = NULL;
		ce->__set = NULL;
		ce->__unset = NULL;
		ce->__isset = NULL;
		ce->__call = NULL;
		ce->__callstatic = NULL;
		ce->__tostring = NULL;
		ce->__serialize = NULL;
		ce->__unserialize = NULL;
		ce->__debugInfo = NULL;
		ce->create_object = NULL;
		ce->get_iterator = NULL;
		ce->iterator_funcs_ptr = NULL;
		ce->arrayaccess_funcs_ptr = NULL;
		ce->get_static_method = NULL;
		ce->parent = NULL;
		ce->parent_name = NULL;
		ce->num_interfaces = 0;
		ce->interfaces = NULL;
		ce->num_traits = 0;
		ce->num_hooked_props = 0;
		ce->num_hooked_prop_variance_checks = 0;
		ce->trait_names = NULL;
		ce->trait_aliases = NULL;
		ce->trait_precedences = NULL;
		ce->serialize = NULL;
		ce->unserialize = NULL;
		if (ce->type == ZEND_INTERNAL_CLASS) {
			ce->info.internal.module = NULL;
			ce->info.internal.builtin_functions = NULL;
		}
	}
}
/* }}} */

ZEND_API zend_string *zend_get_compiled_variable_name(const zend_op_array *op_array, uint32_t var) /* {{{ */
{
	return op_array->vars[EX_VAR_TO_NUM(var)];
}
/* }}} */

zend_ast *zend_ast_append_str(zend_ast *left_ast, zend_ast *right_ast) /* {{{ */
{
	zval *left_zv = zend_ast_get_zval(left_ast);
	zend_string *left = Z_STR_P(left_zv);
	zend_string *right = zend_ast_get_str(right_ast);

	zend_string *result;
	size_t left_len = ZSTR_LEN(left);
	size_t len = left_len + ZSTR_LEN(right) + 1; /* left\right */

	result = zend_string_extend(left, len, 0);
	ZSTR_VAL(result)[left_len] = '\\';
	memcpy(&ZSTR_VAL(result)[left_len + 1], ZSTR_VAL(right), ZSTR_LEN(right));
	ZSTR_VAL(result)[len] = '\0';
	zend_string_release_ex(right, 0);

	ZVAL_STR(left_zv, result);
	return left_ast;
}
/* }}} */

zend_ast *zend_negate_num_string(zend_ast *ast) /* {{{ */
{
	zval *zv = zend_ast_get_zval(ast);
	if (Z_TYPE_P(zv) == IS_LONG) {
		if (Z_LVAL_P(zv) == 0) {
			ZVAL_NEW_STR(zv, ZSTR_INIT_LITERAL("-0", 0));
		} else {
			ZEND_ASSERT(Z_LVAL_P(zv) > 0);
			Z_LVAL_P(zv) *= -1;
		}
	} else if (Z_TYPE_P(zv) == IS_STRING) {
		size_t orig_len = Z_STRLEN_P(zv);
		Z_STR_P(zv) = zend_string_extend(Z_STR_P(zv), orig_len + 1, 0);
		memmove(Z_STRVAL_P(zv) + 1, Z_STRVAL_P(zv), orig_len + 1);
		Z_STRVAL_P(zv)[0] = '-';
	} else {
		ZEND_UNREACHABLE();
	}
	return ast;
}
/* }}} */

static void zend_verify_namespace(void) /* {{{ */
{
	if (FC(has_bracketed_namespaces) && !FC(in_namespace)) {
		zend_error_noreturn(E_COMPILE_ERROR, "No code may exist outside of namespace {}");
	}
}
/* }}} */

/* {{{ zend_dirname
   Returns directory name component of path */
ZEND_API size_t zend_dirname(char *path, size_t len)
{
	char *end = path + len - 1;
	unsigned int len_adjust = 0;

#ifdef ZEND_WIN32
	/* Note that on Win32 CWD is per drive (heritage from CP/M).
	 * This means dirname("c:foo") maps to "c:." or "c:" - which means CWD on C: drive.
	 */
	if ((2 <= len) && isalpha((int)((unsigned char *)path)[0]) && (':' == path[1])) {
		/* Skip over the drive spec (if any) so as not to change */
		path += 2;
		len_adjust += 2;
		if (2 == len) {
			/* Return "c:" on Win32 for dirname("c:").
			 * It would be more consistent to return "c:."
			 * but that would require making the string *longer*.
			 */
			return len;
		}
	}
#endif

	if (len == 0) {
		/* Illegal use of this function */
		return 0;
	}

	/* Strip trailing slashes */
	while (end >= path && IS_SLASH_P_EX(end, end == path)) {
		end--;
	}
	if (end < path) {
		/* The path only contained slashes */
		path[0] = DEFAULT_SLASH;
		path[1] = '\0';
		return 1 + len_adjust;
	}

	/* Strip filename */
	while (end >= path && !IS_SLASH_P_EX(end, end == path)) {
		end--;
	}
	if (end < path) {
		/* No slash found, therefore return '.' */
		path[0] = '.';
		path[1] = '\0';
		return 1 + len_adjust;
	}

	/* Strip slashes which came before the file name */
	while (end >= path && IS_SLASH_P_EX(end, end == path)) {
		end--;
	}
	if (end < path) {
		path[0] = DEFAULT_SLASH;
		path[1] = '\0';
		return 1 + len_adjust;
	}
	*(end+1) = '\0';

	return (size_t)(end + 1 - path) + len_adjust;
}
/* }}} */

static void zend_adjust_for_fetch_type(zend_op *opline, znode *result, uint32_t type) /* {{{ */
{
	uint_fast8_t factor = (opline->opcode == ZEND_FETCH_STATIC_PROP_R) ? 1 : 3;

	switch (type) {
		case BP_VAR_R:
			opline->result_type = IS_TMP_VAR;
			result->op_type = IS_TMP_VAR;
			return;
		case BP_VAR_W:
			opline->opcode += 1 * factor;
			return;
		case BP_VAR_RW:
			opline->opcode += 2 * factor;
			return;
		case BP_VAR_IS:
			opline->result_type = IS_TMP_VAR;
			result->op_type = IS_TMP_VAR;
			opline->opcode += 3 * factor;
			return;
		case BP_VAR_FUNC_ARG:
			opline->opcode += 4 * factor;
			return;
		case BP_VAR_UNSET:
			opline->opcode += 5 * factor;
			return;
		EMPTY_SWITCH_DEFAULT_CASE()
	}
}
/* }}} */

static inline void zend_make_var_result(znode *result, zend_op *opline) /* {{{ */
{
	opline->result_type = IS_VAR;
	opline->result.var = get_temporary_variable();
	GET_NODE(result, opline->result);
}
/* }}} */

static inline void zend_make_tmp_result(znode *result, zend_op *opline) /* {{{ */
{
	opline->result_type = IS_TMP_VAR;
	opline->result.var = get_temporary_variable();
	GET_NODE(result, opline->result);
}
/* }}} */

static zend_op *zend_emit_op(znode *result, uint8_t opcode, znode *op1, znode *op2) /* {{{ */
{
	zend_op *opline = get_next_op();
	opline->opcode = opcode;

	if (op1 != NULL) {
		SET_NODE(opline->op1, op1);
	}

	if (op2 != NULL) {
		SET_NODE(opline->op2, op2);
	}

	if (result) {
		zend_make_var_result(result, opline);
	}
	return opline;
}
/* }}} */

static zend_op *zend_emit_op_tmp(znode *result, uint8_t opcode, znode *op1, znode *op2) /* {{{ */
{
	zend_op *opline = get_next_op();
	opline->opcode = opcode;

	if (op1 != NULL) {
		SET_NODE(opline->op1, op1);
	}

	if (op2 != NULL) {
		SET_NODE(opline->op2, op2);
	}

	if (result) {
		zend_make_tmp_result(result, opline);
	}

	return opline;
}
/* }}} */

static void zend_emit_tick(void) /* {{{ */
{
	zend_op *opline;

	/* This prevents a double TICK generated by the parser statement of "declare()" */
	if (CG(active_op_array)->last && CG(active_op_array)->opcodes[CG(active_op_array)->last - 1].opcode == ZEND_TICKS) {
		return;
	}

	opline = get_next_op();

	opline->opcode = ZEND_TICKS;
	opline->extended_value = FC(declarables).ticks;
}
/* }}} */

static inline zend_op *zend_emit_op_data(znode *value) /* {{{ */
{
	return zend_emit_op(NULL, ZEND_OP_DATA, value, NULL);
}
/* }}} */

static inline uint32_t zend_emit_jump(uint32_t opnum_target) /* {{{ */
{
	uint32_t opnum = get_next_op_number();
	zend_op *opline = zend_emit_op(NULL, ZEND_JMP, NULL, NULL);
	opline->op1.opline_num = opnum_target;
	return opnum;
}
/* }}} */

ZEND_API bool zend_is_smart_branch(const zend_op *opline) /* {{{ */
{
	switch (opline->opcode) {
		case ZEND_IS_IDENTICAL:
		case ZEND_IS_NOT_IDENTICAL:
		case ZEND_IS_EQUAL:
		case ZEND_IS_NOT_EQUAL:
		case ZEND_IS_SMALLER:
		case ZEND_IS_SMALLER_OR_EQUAL:
		case ZEND_CASE:
		case ZEND_CASE_STRICT:
		case ZEND_ISSET_ISEMPTY_CV:
		case ZEND_ISSET_ISEMPTY_VAR:
		case ZEND_ISSET_ISEMPTY_DIM_OBJ:
		case ZEND_ISSET_ISEMPTY_PROP_OBJ:
		case ZEND_ISSET_ISEMPTY_STATIC_PROP:
		case ZEND_INSTANCEOF:
		case ZEND_TYPE_CHECK:
		case ZEND_DEFINED:
		case ZEND_IN_ARRAY:
		case ZEND_ARRAY_KEY_EXISTS:
			return 1;
		default:
			return 0;
	}
}
/* }}} */

static inline uint32_t zend_emit_cond_jump(uint8_t opcode, znode *cond, uint32_t opnum_target) /* {{{ */
{
	uint32_t opnum = get_next_op_number();
	zend_op *opline;

	if (cond->op_type == IS_TMP_VAR && opnum > 0) {
		opline = CG(active_op_array)->opcodes + opnum - 1;
		if (opline->result_type == IS_TMP_VAR
		 && opline->result.var == cond->u.op.var
		 && zend_is_smart_branch(opline)) {
			if (opcode == ZEND_JMPZ) {
				opline->result_type = IS_TMP_VAR | IS_SMART_BRANCH_JMPZ;
			} else {
				ZEND_ASSERT(opcode == ZEND_JMPNZ);
				opline->result_type = IS_TMP_VAR | IS_SMART_BRANCH_JMPNZ;
			}
		}
	}
	opline = zend_emit_op(NULL, opcode, cond, NULL);
	opline->op2.opline_num = opnum_target;
	return opnum;
}
/* }}} */

static inline void zend_update_jump_target(uint32_t opnum_jump, uint32_t opnum_target) /* {{{ */
{
	zend_op *opline = &CG(active_op_array)->opcodes[opnum_jump];
	switch (opline->opcode) {
		case ZEND_JMP:
			opline->op1.opline_num = opnum_target;
			break;
		case ZEND_JMPZ:
		case ZEND_JMPNZ:
		case ZEND_JMPZ_EX:
		case ZEND_JMPNZ_EX:
		case ZEND_JMP_SET:
		case ZEND_COALESCE:
		case ZEND_JMP_NULL:
		case ZEND_BIND_INIT_STATIC_OR_JMP:
		case ZEND_JMP_FRAMELESS:
			opline->op2.opline_num = opnum_target;
			break;
		EMPTY_SWITCH_DEFAULT_CASE()
	}
}
/* }}} */

static inline void zend_update_jump_target_to_next(uint32_t opnum_jump) /* {{{ */
{
	zend_update_jump_target(opnum_jump, get_next_op_number());
}
/* }}} */

static inline zend_op *zend_delayed_emit_op(znode *result, uint8_t opcode, znode *op1, znode *op2) /* {{{ */
{
	zend_op tmp_opline;

	init_op(&tmp_opline);

	tmp_opline.opcode = opcode;
	if (op1 != NULL) {
		SET_NODE(tmp_opline.op1, op1);
	}
	if (op2 != NULL) {
		SET_NODE(tmp_opline.op2, op2);
	}
	if (result) {
		zend_make_var_result(result, &tmp_opline);
	}

	zend_stack_push(&CG(delayed_oplines_stack), &tmp_opline);
	return zend_stack_top(&CG(delayed_oplines_stack));
}
/* }}} */

static inline uint32_t zend_delayed_compile_begin(void) /* {{{ */
{
	return zend_stack_count(&CG(delayed_oplines_stack));
}
/* }}} */

static zend_op *zend_delayed_compile_end(uint32_t offset) /* {{{ */
{
	zend_op *opline = NULL, *oplines = zend_stack_base(&CG(delayed_oplines_stack));
	uint32_t i, count = zend_stack_count(&CG(delayed_oplines_stack));

	ZEND_ASSERT(count >= offset);
	for (i = offset; i < count; ++i) {
		if (EXPECTED(oplines[i].opcode != ZEND_NOP)) {
			opline = get_next_op();
			memcpy(opline, &oplines[i], sizeof(zend_op));
		} else {
			opline = CG(active_op_array)->opcodes + oplines[i].extended_value;
		}
	}

	CG(delayed_oplines_stack).top = offset;
	return opline;
}
/* }}} */

static bool zend_ast_kind_is_short_circuited(zend_ast_kind ast_kind)
{
	switch (ast_kind) {
		case ZEND_AST_DIM:
		case ZEND_AST_PROP:
		case ZEND_AST_NULLSAFE_PROP:
		case ZEND_AST_STATIC_PROP:
		case ZEND_AST_METHOD_CALL:
		case ZEND_AST_NULLSAFE_METHOD_CALL:
		case ZEND_AST_STATIC_CALL:
			return 1;
		default:
			return 0;
	}
}

static bool zend_ast_is_short_circuited(const zend_ast *ast)
{
	switch (ast->kind) {
		case ZEND_AST_DIM:
		case ZEND_AST_PROP:
		case ZEND_AST_STATIC_PROP:
		case ZEND_AST_METHOD_CALL:
		case ZEND_AST_STATIC_CALL:
			return zend_ast_is_short_circuited(ast->child[0]);
		case ZEND_AST_NULLSAFE_PROP:
		case ZEND_AST_NULLSAFE_METHOD_CALL:
			return 1;
		default:
			return 0;
	}
}

static void zend_assert_not_short_circuited(const zend_ast *ast)
{
	if (zend_ast_is_short_circuited(ast)) {
		zend_error_noreturn(E_COMPILE_ERROR, "Cannot take reference of a nullsafe chain");
	}
}

/* Mark nodes that are an inner part of a short-circuiting chain.
 * We should not perform a "commit" on them, as it will be performed by the outer-most node.
 * We do this to avoid passing down an argument in various compile functions. */

#define ZEND_SHORT_CIRCUITING_INNER 0x8000

static void zend_short_circuiting_mark_inner(zend_ast *ast) {
	if (zend_ast_kind_is_short_circuited(ast->kind)) {
		ast->attr |= ZEND_SHORT_CIRCUITING_INNER;
	}
}

static uint32_t zend_short_circuiting_checkpoint(void)
{
	return zend_stack_count(&CG(short_circuiting_opnums));
}

static void zend_short_circuiting_commit(uint32_t checkpoint, znode *result, const zend_ast *ast)
{
	bool is_short_circuited = zend_ast_kind_is_short_circuited(ast->kind)
		|| ast->kind == ZEND_AST_ISSET || ast->kind == ZEND_AST_EMPTY;
	if (!is_short_circuited) {
		ZEND_ASSERT(zend_stack_count(&CG(short_circuiting_opnums)) == checkpoint
			&& "Short circuiting stack should be empty");
		return;
	}

	if (ast->attr & ZEND_SHORT_CIRCUITING_INNER) {
		/* Outer-most node will commit. */
		return;
	}

	while (zend_stack_count(&CG(short_circuiting_opnums)) != checkpoint) {
		uint32_t opnum = *(uint32_t *) zend_stack_top(&CG(short_circuiting_opnums));
		zend_op *opline = &CG(active_op_array)->opcodes[opnum];
		opline->op2.opline_num = get_next_op_number();
		SET_NODE(opline->result, result);
		opline->extended_value |=
			ast->kind == ZEND_AST_ISSET ? ZEND_SHORT_CIRCUITING_CHAIN_ISSET :
			ast->kind == ZEND_AST_EMPTY ? ZEND_SHORT_CIRCUITING_CHAIN_EMPTY :
			                              ZEND_SHORT_CIRCUITING_CHAIN_EXPR;
		zend_stack_del_top(&CG(short_circuiting_opnums));
	}
}

static void zend_emit_jmp_null(znode *obj_node, uint32_t bp_type)
{
	uint32_t jmp_null_opnum = get_next_op_number();
	zend_op *opline = zend_emit_op(NULL, ZEND_JMP_NULL, obj_node, NULL);
	if (opline->op1_type == IS_CONST) {
		Z_TRY_ADDREF_P(CT_CONSTANT(opline->op1));
	}
	if (bp_type == BP_VAR_IS) {
		opline->extended_value |= ZEND_JMP_NULL_BP_VAR_IS;
	}
	zend_stack_push(&CG(short_circuiting_opnums), &jmp_null_opnum);
}

static inline bool zend_is_variable_or_call(const zend_ast *ast);

static void zend_compile_memoized_expr(znode *result, zend_ast *expr, uint32_t type) /* {{{ */
{
	const zend_memoize_mode memoize_mode = CG(memoize_mode);
	if (memoize_mode == ZEND_MEMOIZE_COMPILE) {
		znode memoized_result;

		/* Go through normal compilation */
		CG(memoize_mode) = ZEND_MEMOIZE_NONE;
		if (zend_is_variable_or_call(expr)) {
			zend_compile_var(result, expr, type, /* by_ref */ false);
		} else {
			zend_compile_expr(result, expr);
		}
		CG(memoize_mode) = ZEND_MEMOIZE_COMPILE;

		if (result->op_type == IS_VAR) {
			zend_emit_op(&memoized_result, ZEND_COPY_TMP, result, NULL);
		} else if (result->op_type == IS_TMP_VAR) {
			zend_emit_op_tmp(&memoized_result, ZEND_COPY_TMP, result, NULL);
		} else {
			if (result->op_type == IS_CONST) {
				Z_TRY_ADDREF(result->u.constant);
			}
			memoized_result = *result;
		}

		zend_hash_index_update_mem(
			CG(memoized_exprs), (uintptr_t) expr, &memoized_result, sizeof(znode));
	} else if (memoize_mode == ZEND_MEMOIZE_FETCH) {
		const znode *memoized_result = zend_hash_index_find_ptr(CG(memoized_exprs), (uintptr_t) expr);
		*result = *memoized_result;
		if (result->op_type == IS_CONST) {
			Z_TRY_ADDREF(result->u.constant);
		}
	} else {
		ZEND_UNREACHABLE();
	}
}
/* }}} */

static void zend_emit_return_type_check(
		znode *expr, const zend_arg_info *return_info, bool implicit) /* {{{ */
{
	zend_type type = return_info->type;
	if (ZEND_TYPE_IS_SET(type)) {
		zend_op *opline;

		/* `return ...;` is illegal in a void function (but `return;` isn't) */
		if (ZEND_TYPE_CONTAINS_CODE(type, IS_VOID)) {
			if (expr) {
				if (expr->op_type == IS_CONST && Z_TYPE(expr->u.constant) == IS_NULL) {
					zend_error_noreturn(E_COMPILE_ERROR,
						"A void %s must not return a value "
						"(did you mean \"return;\" instead of \"return null;\"?)",
						CG(active_class_entry) != NULL ? "method" : "function");
				} else {
					zend_error_noreturn(E_COMPILE_ERROR, "A void %s must not return a value",
					CG(active_class_entry) != NULL ? "method" : "function");
				}
			}
			/* we don't need run-time check */
			return;
		}

		/* `return` is illegal in a never-returning function */
		if (ZEND_TYPE_CONTAINS_CODE(type, IS_NEVER)) {
			/* Implicit case handled separately using VERIFY_NEVER_TYPE opcode. */
			ZEND_ASSERT(!implicit);
			zend_error_noreturn(E_COMPILE_ERROR, "A never-returning %s must not return",
				CG(active_class_entry) != NULL ? "method" : "function");
		}

		if (!expr && !implicit) {
			if (ZEND_TYPE_ALLOW_NULL(type)) {
				zend_error_noreturn(E_COMPILE_ERROR,
					"A %s with return type must return a value "
					"(did you mean \"return null;\" instead of \"return;\"?)",
					CG(active_class_entry) != NULL ? "method" : "function");
			} else {
				zend_error_noreturn(E_COMPILE_ERROR,
					"A %s with return type must return a value",
					CG(active_class_entry) != NULL ? "method" : "function");
			}
		}

		if (expr && ZEND_TYPE_PURE_MASK(type) == MAY_BE_ANY) {
			/* we don't need run-time check for mixed return type */
			return;
		}

		if (expr && expr->op_type == IS_CONST && ZEND_TYPE_CONTAINS_CODE(type, Z_TYPE(expr->u.constant))) {
			/* we don't need run-time check */
			return;
		}

		opline = zend_emit_op(NULL, ZEND_VERIFY_RETURN_TYPE, expr, NULL);
		if (expr && expr->op_type == IS_CONST) {
			opline->result_type = expr->op_type = IS_TMP_VAR;
			opline->result.var = expr->u.op.var = get_temporary_variable();
		}
	}
}
/* }}} */

void zend_emit_final_return(bool return_one) /* {{{ */
{
	znode zn;
	zend_op *ret;
	bool returns_reference = (CG(active_op_array)->fn_flags & ZEND_ACC_RETURN_REFERENCE) != 0;

	if ((CG(active_op_array)->fn_flags & ZEND_ACC_HAS_RETURN_TYPE)
			&& !(CG(active_op_array)->fn_flags & ZEND_ACC_GENERATOR)) {
		zend_arg_info *return_info = CG(active_op_array)->arg_info - 1;

		if (ZEND_TYPE_CONTAINS_CODE(return_info->type, IS_NEVER)) {
			zend_emit_op(NULL, ZEND_VERIFY_NEVER_TYPE, NULL, NULL);
			return;
		}

		zend_emit_return_type_check(NULL, return_info, true);
	}

	zn.op_type = IS_CONST;
	if (return_one) {
		ZVAL_LONG(&zn.u.constant, 1);
	} else {
		ZVAL_NULL(&zn.u.constant);
	}

	ret = zend_emit_op(NULL, returns_reference ? ZEND_RETURN_BY_REF : ZEND_RETURN, &zn, NULL);
	ret->extended_value = -1;
}
/* }}} */

static inline bool zend_is_variable(const zend_ast *ast) /* {{{ */
{
	return ast->kind == ZEND_AST_VAR
		|| ast->kind == ZEND_AST_DIM
		|| ast->kind == ZEND_AST_PROP
		|| ast->kind == ZEND_AST_NULLSAFE_PROP
		|| ast->kind == ZEND_AST_STATIC_PROP;
}
/* }}} */

static bool zend_propagate_list_refs(zend_ast *ast);

static inline bool zend_is_passable_by_ref(const zend_ast *ast)
{
	if (zend_is_variable(ast) || ast->kind == ZEND_AST_ASSIGN_REF) {
		return true;
	}
	if (ast->kind == ZEND_AST_ASSIGN
	 && UNEXPECTED(ast->child[0]->kind == ZEND_AST_ARRAY)
	 && zend_propagate_list_refs(ast->child[0])) {
		return true;
	}
	return false;
}

static inline bool zend_is_call(const zend_ast *ast) /* {{{ */
{
	return ast->kind == ZEND_AST_CALL
		|| ast->kind == ZEND_AST_METHOD_CALL
		|| ast->kind == ZEND_AST_NULLSAFE_METHOD_CALL
		|| ast->kind == ZEND_AST_STATIC_CALL
		|| ast->kind == ZEND_AST_PIPE;
}
/* }}} */

static inline bool zend_is_variable_or_call(const zend_ast *ast) /* {{{ */
{
	return zend_is_variable(ast) || zend_is_call(ast);
}
/* }}} */

static inline bool zend_is_unticked_stmt(const zend_ast *ast) /* {{{ */
{
	return ast->kind == ZEND_AST_STMT_LIST || ast->kind == ZEND_AST_LABEL
		|| ast->kind == ZEND_AST_PROP_DECL || ast->kind == ZEND_AST_CLASS_CONST_GROUP
		|| ast->kind == ZEND_AST_USE_TRAIT || ast->kind == ZEND_AST_METHOD;
}
/* }}} */

static inline bool zend_can_write_to_variable(const zend_ast *ast) /* {{{ */
{
	while (
		ast->kind == ZEND_AST_DIM
		|| ast->kind == ZEND_AST_PROP
	) {
		ast = ast->child[0];
	}

	return zend_is_variable_or_call(ast) && !zend_ast_is_short_circuited(ast);
}
/* }}} */

static inline bool zend_is_const_default_class_ref(zend_ast *name_ast) /* {{{ */
{
	if (name_ast->kind != ZEND_AST_ZVAL) {
		return 0;
	}

	return ZEND_FETCH_CLASS_DEFAULT == zend_get_class_fetch_type_ast(name_ast);
}
/* }}} */

static inline void zend_handle_numeric_op(znode *node) /* {{{ */
{
	if (node->op_type == IS_CONST && Z_TYPE(node->u.constant) == IS_STRING) {
		zend_ulong index;

		if (ZEND_HANDLE_NUMERIC(Z_STR(node->u.constant), index)) {
			zval_ptr_dtor(&node->u.constant);
			ZVAL_LONG(&node->u.constant, index);
		}
	}
}
/* }}} */

static inline void zend_handle_numeric_dim(const zend_op *opline, znode *dim_node) /* {{{ */
{
	if (Z_TYPE(dim_node->u.constant) == IS_STRING) {
		zend_ulong index;

		if (ZEND_HANDLE_NUMERIC(Z_STR(dim_node->u.constant), index)) {
			/* For numeric indexes we also keep the original value to use by ArrayAccess
			 * See bug #63217
			 */
			int c = zend_add_literal(&dim_node->u.constant);
			ZEND_ASSERT(opline->op2.constant + 1 == c);
			ZVAL_LONG(CT_CONSTANT(opline->op2), index);
			Z_EXTRA_P(CT_CONSTANT(opline->op2)) = ZEND_EXTRA_VALUE;
			return;
		}
	}
}
/* }}} */

static inline void zend_set_class_name_op1(zend_op *opline, znode *class_node) /* {{{ */
{
	if (class_node->op_type == IS_CONST) {
		opline->op1_type = IS_CONST;
		opline->op1.constant = zend_add_class_name_literal(
			Z_STR(class_node->u.constant));
	} else {
		SET_NODE(opline->op1, class_node);
	}
}
/* }}} */

static void zend_compile_class_ref(znode *result, zend_ast *name_ast, uint32_t fetch_flags) /* {{{ */
{
	uint32_t fetch_type;

	if (name_ast->kind != ZEND_AST_ZVAL) {
		znode name_node;

		zend_compile_expr(&name_node, name_ast);

		if (name_node.op_type == IS_CONST) {
			zend_string *name;

			if (Z_TYPE(name_node.u.constant) != IS_STRING) {
				zend_error_noreturn(E_COMPILE_ERROR, "Illegal class name");
			}

			name = Z_STR(name_node.u.constant);
			fetch_type = zend_get_class_fetch_type(name);

			if (fetch_type == ZEND_FETCH_CLASS_DEFAULT) {
				result->op_type = IS_CONST;
				ZVAL_STR(&result->u.constant, zend_resolve_class_name(name, ZEND_NAME_FQ));
			} else {
				zend_ensure_valid_class_fetch_type(fetch_type);
				result->op_type = IS_UNUSED;
				result->u.op.num = fetch_type | fetch_flags;
			}

			zend_string_release_ex(name, 0);
		} else {
			zend_op *opline = zend_emit_op(result, ZEND_FETCH_CLASS, NULL, &name_node);
			opline->op1.num = ZEND_FETCH_CLASS_DEFAULT | fetch_flags;
		}
		return;
	}

	/* Fully qualified names are always default refs */
	if (name_ast->attr == ZEND_NAME_FQ) {
		result->op_type = IS_CONST;
		ZVAL_STR(&result->u.constant, zend_resolve_class_name_ast(name_ast));
		return;
	}

	fetch_type = zend_get_class_fetch_type(zend_ast_get_str(name_ast));
	if (ZEND_FETCH_CLASS_DEFAULT == fetch_type) {
		result->op_type = IS_CONST;
		ZVAL_STR(&result->u.constant, zend_resolve_class_name_ast(name_ast));
	} else {
		zend_ensure_valid_class_fetch_type(fetch_type);
		result->op_type = IS_UNUSED;
		result->u.op.num = fetch_type | fetch_flags;
	}
}
/* }}} */

static zend_result zend_try_compile_cv(znode *result, const zend_ast *ast, uint32_t type) /* {{{ */
{
	zend_ast *name_ast = ast->child[0];
	if (name_ast->kind == ZEND_AST_ZVAL) {
		zval *zv = zend_ast_get_zval(name_ast);
		zend_string *name;

		if (EXPECTED(Z_TYPE_P(zv) == IS_STRING)) {
			name = zval_make_interned_string(zv);
		} else {
			name = zend_new_interned_string(zval_get_string_func(zv));
		}

		if (zend_is_auto_global(name)) {
			return FAILURE;
		}

		if (!CG(context).has_assigned_to_http_response_header && zend_string_equals_literal(name, "http_response_header")) {
			if (type == BP_VAR_R) {
				zend_error(E_DEPRECATED,
					"The predefined locally scoped $http_response_header variable is deprecated,"
					" call http_get_last_response_headers() instead");
			} else if (type == BP_VAR_W) {
				CG(context).has_assigned_to_http_response_header = true;
			}
		}

		result->op_type = IS_CV;
		result->u.op.var = lookup_cv(name);

		if (UNEXPECTED(Z_TYPE_P(zv) != IS_STRING)) {
			zend_string_release_ex(name, 0);
		}

		return SUCCESS;
	}

	return FAILURE;
}
/* }}} */

static zend_op *zend_compile_simple_var_no_cv(znode *result, const zend_ast *ast, uint32_t type, bool delayed) /* {{{ */
{
	zend_ast *name_ast = ast->child[0];
	znode name_node;
	zend_op *opline;

	zend_compile_expr(&name_node, name_ast);
	if (name_node.op_type == IS_CONST) {
		convert_to_string(&name_node.u.constant);
	}

	if (delayed) {
		opline = zend_delayed_emit_op(result, ZEND_FETCH_R, &name_node, NULL);
	} else {
		opline = zend_emit_op(result, ZEND_FETCH_R, &name_node, NULL);
	}

	if (name_node.op_type == IS_CONST &&
	    zend_is_auto_global(Z_STR(name_node.u.constant))) {

		opline->extended_value = ZEND_FETCH_GLOBAL;
	} else {
		// TODO: Have a test case for this?
		if (name_node.op_type == IS_CONST
			&& type == BP_VAR_R
			&& zend_string_equals_literal(Z_STR(name_node.u.constant), "http_response_header")) {
			zend_error(E_DEPRECATED,
				"The predefined locally scoped $http_response_header variable is deprecated,"
				" call http_get_last_response_headers() instead");
		}
		opline->extended_value = ZEND_FETCH_LOCAL;
	}

	zend_adjust_for_fetch_type(opline, result, type);
	return opline;
}
/* }}} */

static bool is_this_fetch(const zend_ast *ast) /* {{{ */
{
	if (ast->kind == ZEND_AST_VAR && ast->child[0]->kind == ZEND_AST_ZVAL) {
		const zval *name = zend_ast_get_zval(ast->child[0]);
		return Z_TYPE_P(name) == IS_STRING && zend_string_equals(Z_STR_P(name), ZSTR_KNOWN(ZEND_STR_THIS));
	}

	return 0;
}
/* }}} */

static bool is_globals_fetch(const zend_ast *ast)
{
	if (ast->kind == ZEND_AST_VAR && ast->child[0]->kind == ZEND_AST_ZVAL) {
		const zval *name = zend_ast_get_zval(ast->child[0]);
		return Z_TYPE_P(name) == IS_STRING && zend_string_equals_literal(Z_STR_P(name), "GLOBALS");
	}

	return 0;
}

static bool is_global_var_fetch(const zend_ast *ast)
{
	return ast->kind == ZEND_AST_DIM && is_globals_fetch(ast->child[0]);
}

static bool this_guaranteed_exists(void) /* {{{ */
{
	const zend_oparray_context *ctx = &CG(context);
	while (ctx) {
		/* Instance methods always have a $this.
		 * This also includes closures that have a scope and use $this. */
		const zend_op_array *op_array = ctx->op_array;
		if (op_array->fn_flags & ZEND_ACC_STATIC) {
			return false;
		} else if (op_array->scope) {
			return true;
		} else if (!(op_array->fn_flags & ZEND_ACC_CLOSURE)) {
			return false;
		}
		ctx = ctx->prev;
	}
	return false;
}
/* }}} */

static zend_op *zend_compile_simple_var(znode *result, const zend_ast *ast, uint32_t type, bool delayed) /* {{{ */
{
	if (is_this_fetch(ast)) {
		zend_op *opline = zend_emit_op(result, ZEND_FETCH_THIS, NULL, NULL);
		if ((type == BP_VAR_R) || (type == BP_VAR_IS)) {
			opline->result_type = IS_TMP_VAR;
			result->op_type = IS_TMP_VAR;
		}
		CG(active_op_array)->fn_flags |= ZEND_ACC_USES_THIS;
		return opline;
	} else if (is_globals_fetch(ast)) {
		zend_op *opline = zend_emit_op(result, ZEND_FETCH_GLOBALS, NULL, NULL);
		if (type == BP_VAR_R || type == BP_VAR_IS) {
			opline->result_type = IS_TMP_VAR;
			result->op_type = IS_TMP_VAR;
		}
		return opline;
	} else if (zend_try_compile_cv(result, ast, type) == FAILURE) {
		return zend_compile_simple_var_no_cv(result, ast, type, delayed);
	}
	return NULL;
}
/* }}} */

static void zend_separate_if_call_and_write(znode *node, const zend_ast *ast, uint32_t type) /* {{{ */
{
	if (type != BP_VAR_R
	 && type != BP_VAR_IS
	 /* Whether a FUNC_ARG is R may only be determined at runtime. */
	 && type != BP_VAR_FUNC_ARG
	 && zend_is_call(ast)) {
		if (node->op_type == IS_VAR) {
			zend_op *opline = zend_emit_op(NULL, ZEND_SEPARATE, node, NULL);
			opline->result_type = IS_VAR;
			opline->result.var = opline->op1.var;
		} else {
			zend_error_noreturn(E_COMPILE_ERROR, "Cannot use result of built-in function in write context");
		}
	}
}
/* }}} */

static inline void zend_emit_assign_znode(zend_ast *var_ast, const znode *value_node) /* {{{ */
{
	znode dummy_node;
	zend_ast *assign_ast = zend_ast_create(ZEND_AST_ASSIGN, var_ast,
		zend_ast_create_znode(value_node));
	zend_compile_expr(&dummy_node, assign_ast);
	zend_do_free(&dummy_node);
}
/* }}} */

static zend_op *zend_delayed_compile_dim(znode *result, zend_ast *ast, uint32_t type, bool by_ref)
{
	zend_ast *var_ast = ast->child[0];
	zend_ast *dim_ast = ast->child[1];
	zend_op *opline;

	znode var_node, dim_node;

	if (is_globals_fetch(var_ast)) {
		if (dim_ast == NULL) {
			zend_error_noreturn(E_COMPILE_ERROR, "Cannot append to $GLOBALS");
		}

		zend_compile_expr(&dim_node, dim_ast);
		if (dim_node.op_type == IS_CONST) {
			convert_to_string(&dim_node.u.constant);
		}

		opline = zend_delayed_emit_op(result, ZEND_FETCH_R, &dim_node, NULL);
		opline->extended_value = ZEND_FETCH_GLOBAL;
		zend_adjust_for_fetch_type(opline, result, type);
		return opline;
	} else {
		zend_short_circuiting_mark_inner(var_ast);
		opline = zend_delayed_compile_var(&var_node, var_ast, type, false);
		if (opline) {
			if (type == BP_VAR_W && (opline->opcode == ZEND_FETCH_STATIC_PROP_W || opline->opcode == ZEND_FETCH_OBJ_W)) {
				opline->extended_value |= ZEND_FETCH_DIM_WRITE;
			} else if (opline->opcode == ZEND_FETCH_DIM_W
					|| opline->opcode == ZEND_FETCH_DIM_RW
					|| opline->opcode == ZEND_FETCH_DIM_FUNC_ARG
					|| opline->opcode == ZEND_FETCH_DIM_UNSET) {
				opline->extended_value = ZEND_FETCH_DIM_DIM;
			}
		}
	}

	zend_separate_if_call_and_write(&var_node, var_ast, type);

	if (dim_ast == NULL) {
		if (type == BP_VAR_R || type == BP_VAR_IS) {
			zend_error_noreturn(E_COMPILE_ERROR, "Cannot use [] for reading");
		}
		if (type == BP_VAR_UNSET) {
			zend_error_noreturn(E_COMPILE_ERROR, "Cannot use [] for unsetting");
		}
		dim_node.op_type = IS_UNUSED;
	} else {
		zend_compile_expr(&dim_node, dim_ast);
	}

	opline = zend_delayed_emit_op(result, ZEND_FETCH_DIM_R, &var_node, &dim_node);
	zend_adjust_for_fetch_type(opline, result, type);
	if (by_ref) {
		opline->extended_value = ZEND_FETCH_DIM_REF;
	}

	if (dim_node.op_type == IS_CONST) {
		zend_handle_numeric_dim(opline, &dim_node);
	}
	return opline;
}

static zend_op *zend_compile_dim(znode *result, zend_ast *ast, uint32_t type, bool by_ref) /* {{{ */
{
	uint32_t offset = zend_delayed_compile_begin();
	zend_delayed_compile_dim(result, ast, type, by_ref);
	return zend_delayed_compile_end(offset);
}
/* }}} */

static zend_op *zend_delayed_compile_prop(znode *result, zend_ast *ast, uint32_t type) /* {{{ */
{
	zend_ast *obj_ast = ast->child[0];
	zend_ast *prop_ast = ast->child[1];

	znode obj_node, prop_node;
	zend_op *opline;
	bool nullsafe = ast->kind == ZEND_AST_NULLSAFE_PROP;

	if (is_this_fetch(obj_ast)) {
		if (this_guaranteed_exists()) {
			obj_node.op_type = IS_UNUSED;
		} else {
			opline = zend_emit_op(&obj_node, ZEND_FETCH_THIS, NULL, NULL);
			if ((type == BP_VAR_R) || (type == BP_VAR_IS)) {
				opline->result_type = IS_TMP_VAR;
				obj_node.op_type = IS_TMP_VAR;
			}
		}
		CG(active_op_array)->fn_flags |= ZEND_ACC_USES_THIS;

		/* We will throw if $this doesn't exist, so there's no need to emit a JMP_NULL
		 * check for a nullsafe access. */
	} else {
		zend_short_circuiting_mark_inner(obj_ast);
		opline = zend_delayed_compile_var(&obj_node, obj_ast, type, false);
		if (opline && (opline->opcode == ZEND_FETCH_DIM_W
				|| opline->opcode == ZEND_FETCH_DIM_RW
				|| opline->opcode == ZEND_FETCH_DIM_FUNC_ARG
				|| opline->opcode == ZEND_FETCH_DIM_UNSET)) {
			opline->extended_value = ZEND_FETCH_DIM_OBJ;
		}

		zend_separate_if_call_and_write(&obj_node, obj_ast, type);
		if (nullsafe) {
			if (obj_node.op_type == IS_TMP_VAR) {
				/* Flush delayed oplines */
				zend_op *opline = NULL, *oplines = zend_stack_base(&CG(delayed_oplines_stack));
				uint32_t var = obj_node.u.op.var;
				uint32_t count = zend_stack_count(&CG(delayed_oplines_stack));
				uint32_t i = count;

				while (i > 0 && oplines[i-1].result_type == IS_TMP_VAR && oplines[i-1].result.var == var) {
					i--;
					if (oplines[i].op1_type == IS_TMP_VAR) {
						var = oplines[i].op1.var;
					} else {
						break;
					}
				}
				for (; i < count; ++i) {
					if (oplines[i].opcode != ZEND_NOP) {
						opline = get_next_op();
						memcpy(opline, &oplines[i], sizeof(zend_op));
						oplines[i].opcode = ZEND_NOP;
						oplines[i].extended_value = opline - CG(active_op_array)->opcodes;
					}
				}
			}
			zend_emit_jmp_null(&obj_node, type);
		}
	}

	zend_compile_expr(&prop_node, prop_ast);

	opline = zend_delayed_emit_op(result, ZEND_FETCH_OBJ_R, &obj_node, &prop_node);
	if (opline->op2_type == IS_CONST) {
		convert_to_string(CT_CONSTANT(opline->op2));
		zend_string_hash_val(Z_STR_P(CT_CONSTANT(opline->op2)));
		opline->extended_value = zend_alloc_cache_slots(3);
	}

	zend_adjust_for_fetch_type(opline, result, type);

	return opline;
}
/* }}} */

static zend_op *zend_compile_prop(znode *result, zend_ast *ast, uint32_t type, bool by_ref) /* {{{ */
{
	uint32_t offset = zend_delayed_compile_begin();
	zend_op *opline = zend_delayed_compile_prop(result, ast, type);
	if (by_ref) { /* shared with cache_slot */
		opline->extended_value |= ZEND_FETCH_REF;
	}
	return zend_delayed_compile_end(offset);
}
/* }}} */

static zend_op *zend_compile_static_prop(znode *result, zend_ast *ast, uint32_t type, bool by_ref, bool delayed) /* {{{ */
{
	zend_ast *class_ast = ast->child[0];
	zend_ast *prop_ast = ast->child[1];

	znode class_node, prop_node;
	zend_op *opline;

	zend_short_circuiting_mark_inner(class_ast);
	zend_compile_class_ref(&class_node, class_ast, ZEND_FETCH_CLASS_EXCEPTION);

	zend_compile_expr(&prop_node, prop_ast);

	if (delayed) {
		opline = zend_delayed_emit_op(result, ZEND_FETCH_STATIC_PROP_R, &prop_node, NULL);
	} else {
		opline = zend_emit_op(result, ZEND_FETCH_STATIC_PROP_R, &prop_node, NULL);
	}
	if (opline->op1_type == IS_CONST) {
		convert_to_string(CT_CONSTANT(opline->op1));
		opline->extended_value = zend_alloc_cache_slots(3);
	}
	if (class_node.op_type == IS_CONST) {
		opline->op2_type = IS_CONST;
		opline->op2.constant = zend_add_class_name_literal(
			Z_STR(class_node.u.constant));
		if (opline->op1_type != IS_CONST) {
			opline->extended_value = zend_alloc_cache_slot();
		}
	} else {
		SET_NODE(opline->op2, &class_node);
	}

	if (by_ref && (type == BP_VAR_W || type == BP_VAR_FUNC_ARG)) { /* shared with cache_slot */
		opline->extended_value |= ZEND_FETCH_REF;
	}

	zend_adjust_for_fetch_type(opline, result, type);
	return opline;
}
/* }}} */

static void zend_verify_list_assign_target(const zend_ast *var_ast, zend_ast_attr array_style) /* {{{ */ {
	if (var_ast->kind == ZEND_AST_ARRAY) {
		if (var_ast->attr == ZEND_ARRAY_SYNTAX_LONG) {
			zend_error_noreturn(E_COMPILE_ERROR, "Cannot assign to array(), use [] instead");
		}
		if (array_style != var_ast->attr) {
			zend_error_noreturn(E_COMPILE_ERROR, "Cannot mix [] and list()");
		}
	} else if (!zend_can_write_to_variable(var_ast)) {
		zend_error_noreturn(E_COMPILE_ERROR, "Assignments can only happen to writable values");
	}
}
/* }}} */

static inline void zend_emit_assign_ref_znode(zend_ast *var_ast, const znode *value_node);

/* Propagate refs used on leaf elements to the surrounding list() structures. */
static bool zend_propagate_list_refs(zend_ast *ast) { /* {{{ */
	const zend_ast_list *list = zend_ast_get_list(ast);
	bool has_refs = false;
	uint32_t i;

	for (i = 0; i < list->children; ++i) {
		zend_ast *elem_ast = list->child[i];

		if (elem_ast) {
			zend_ast *var_ast = elem_ast->child[0];
			if (var_ast->kind == ZEND_AST_ARRAY) {
				elem_ast->attr = zend_propagate_list_refs(var_ast);
			}
			has_refs |= elem_ast->attr;
		}
	}

	return has_refs;
}
/* }}} */

static bool list_is_keyed(const zend_ast_list *list)
{
	for (uint32_t i = 0; i < list->children; i++) {
		const zend_ast *child = list->child[i];
		if (child) {
			return child->kind == ZEND_AST_ARRAY_ELEM && child->child[1] != NULL;
		}
	}
	return false;
}

static void zend_compile_list_assign(
		znode *result, zend_ast *ast, znode *expr_node, zend_ast_attr array_style, uint32_t type) /* {{{ */
{
	zend_ast_list *list = zend_ast_get_list(ast);
	uint32_t i;
	bool has_elems = false;
	bool is_keyed = list_is_keyed(list);

	if (list->children && expr_node->op_type == IS_CONST && Z_TYPE(expr_node->u.constant) == IS_STRING) {
		zval_make_interned_string(&expr_node->u.constant);
	}

	for (i = 0; i < list->children; ++i) {
		zend_ast *elem_ast = list->child[i];
		zend_ast *var_ast, *key_ast;
		znode fetch_result, dim_node;
		zend_op *opline;

		if (elem_ast == NULL) {
			if (is_keyed) {
				zend_error(E_COMPILE_ERROR,
					"Cannot use empty array entries in keyed array assignment");
			} else {
				continue;
			}
		}

		if (elem_ast->kind == ZEND_AST_UNPACK) {
			zend_error(E_COMPILE_ERROR,
					"Spread operator is not supported in assignments");
		}

		var_ast = elem_ast->child[0];
		key_ast = elem_ast->child[1];
		has_elems = true;

		if (is_keyed) {
			if (key_ast == NULL) {
				zend_error(E_COMPILE_ERROR,
					"Cannot mix keyed and unkeyed array entries in assignments");
			}

			zend_compile_expr(&dim_node, key_ast);
		} else {
			if (key_ast != NULL) {
				zend_error(E_COMPILE_ERROR,
					"Cannot mix keyed and unkeyed array entries in assignments");
			}

			dim_node.op_type = IS_CONST;
			ZVAL_LONG(&dim_node.u.constant, i);
		}

		if (expr_node->op_type == IS_CONST) {
			Z_TRY_ADDREF(expr_node->u.constant);
		}

		zend_verify_list_assign_target(var_ast, array_style);

		opline = zend_emit_op(&fetch_result,
			elem_ast->attr ? (expr_node->op_type == IS_CV ? ZEND_FETCH_DIM_W : ZEND_FETCH_LIST_W) : ZEND_FETCH_LIST_R, expr_node, &dim_node);
		if (opline->opcode == ZEND_FETCH_LIST_R) {
			opline->result_type = IS_TMP_VAR;
			fetch_result.op_type = IS_TMP_VAR;
		}

		if (dim_node.op_type == IS_CONST) {
			zend_handle_numeric_dim(opline, &dim_node);
		}

		if (elem_ast->attr) {
			zend_emit_op(&fetch_result, ZEND_MAKE_REF, &fetch_result, NULL);
		}
		if (var_ast->kind == ZEND_AST_ARRAY) {
			zend_compile_list_assign(NULL, var_ast, &fetch_result, var_ast->attr, type);
		} else if (elem_ast->attr) {
			zend_emit_assign_ref_znode(var_ast, &fetch_result);
		} else {
			zend_emit_assign_znode(var_ast, &fetch_result);
		}
	}

	if (has_elems == 0) {
		zend_error_noreturn(E_COMPILE_ERROR, "Cannot use empty list");
	}

	if (result) {
		if ((type == BP_VAR_R || type == BP_VAR_IS) && expr_node->op_type == IS_VAR) {
			/* Deref. */
			zend_emit_op_tmp(result, ZEND_QM_ASSIGN, expr_node, NULL);
		} else {
			*result = *expr_node;
		}
	} else {
		zend_do_free(expr_node);
	}
}
/* }}} */

static void zend_ensure_writable_variable(const zend_ast *ast) /* {{{ */
{
	if (ast->kind == ZEND_AST_CALL || ast->kind == ZEND_AST_PIPE) {
		zend_error_noreturn(E_COMPILE_ERROR, "Can't use function return value in write context");
	}
	if (
		ast->kind == ZEND_AST_METHOD_CALL
		|| ast->kind == ZEND_AST_NULLSAFE_METHOD_CALL
		|| ast->kind == ZEND_AST_STATIC_CALL
	) {
		zend_error_noreturn(E_COMPILE_ERROR, "Can't use method return value in write context");
	}
	if (zend_ast_is_short_circuited(ast)) {
		zend_error_noreturn(E_COMPILE_ERROR, "Can't use nullsafe operator in write context");
	}
	if (is_globals_fetch(ast)) {
		zend_error_noreturn(E_COMPILE_ERROR,
			"$GLOBALS can only be modified using the $GLOBALS[$name] = $value syntax");
	}
}
/* }}} */

/* Detects $a... = $a pattern */
static bool zend_is_assign_to_self(const zend_ast *var_ast, const zend_ast *expr_ast) /* {{{ */
{
	if (expr_ast->kind != ZEND_AST_VAR || expr_ast->ch
