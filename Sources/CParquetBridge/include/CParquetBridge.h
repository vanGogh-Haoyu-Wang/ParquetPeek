#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef long long PRQHandle;

PRQHandle prq_open_file(const char *path);
char *prq_load_metadata(PRQHandle handle);
char *prq_load_schema(PRQHandle handle);
char *prq_read_rows(PRQHandle handle, long long offset, int limit, const char *columns_csv);
void prq_cancel(PRQHandle handle);
void prq_close_file(PRQHandle handle);
const char *prq_last_error(void);
void prq_free_string(char *value);

#ifdef __cplusplus
}
#endif
