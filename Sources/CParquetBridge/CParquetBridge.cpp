#include "CParquetBridge.h"

#include <arrow/api.h>
#include <arrow/io/api.h>
#include <arrow/pretty_print.h>
#include <parquet/arrow/reader.h>
#include <parquet/file_reader.h>
#include <parquet/metadata.h>
#include <parquet/schema.h>
#include <parquet/types.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct OpenedFile {
    std::string path;
    std::atomic<bool> cancelled { false };
};

std::mutex g_mutex;
std::unordered_map<PRQHandle, std::shared_ptr<OpenedFile>> g_files;
PRQHandle g_next_handle = 1;
thread_local std::string g_last_error;

void set_error(const std::string &message) {
    g_last_error = message;
}

std::shared_ptr<OpenedFile> lookup(PRQHandle handle) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto found = g_files.find(handle);
    if (found == g_files.end()) {
        set_error("Unknown or closed Parquet file handle.");
        return nullptr;
    }
    return found->second;
}

std::string escape_json(const std::string &value) {
    std::ostringstream out;
    for (unsigned char c : value) {
        switch (c) {
            case '"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\b': out << "\\b"; break;
            case '\f': out << "\\f"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (c < 0x20) {
                    const char *hex = "0123456789abcdef";
                    out << "\\u00" << hex[c >> 4] << hex[c & 0x0f];
                } else {
                    out << c;
                }
        }
    }
    return out.str();
}

std::string quoted(const std::string &value) {
    return "\"" + escape_json(value) + "\"";
}

char *copy_json(const std::string &json) {
    char *buffer = static_cast<char *>(std::malloc(json.size() + 1));
    if (!buffer) {
        set_error("Unable to allocate response buffer.");
        return nullptr;
    }
    std::memcpy(buffer, json.c_str(), json.size() + 1);
    return buffer;
}

std::vector<std::string> split_columns(const char *csv) {
    std::vector<std::string> columns;
    if (!csv || std::strlen(csv) == 0) {
        return columns;
    }

    std::string input(csv);
    std::stringstream stream(input);
    std::string item;
    while (std::getline(stream, item, ',')) {
        if (!item.empty()) {
            columns.push_back(item);
        }
    }
    return columns;
}

std::string arrow_scalar_to_string(const std::shared_ptr<arrow::Scalar> &scalar) {
    if (!scalar || !scalar->is_valid) {
        return "";
    }
    return scalar->ToString();
}

std::string status_message(const arrow::Status &status) {
    return status.ToString();
}

} // namespace

extern "C" PRQHandle prq_open_file(const char *path) {
    g_last_error.clear();
    if (!path || std::strlen(path) == 0) {
        set_error("No file path was provided.");
        return 0;
    }

    try {
        auto reader = parquet::ParquetFileReader::OpenFile(path, false);
        if (!reader || !reader->metadata()) {
            set_error("The file could not be opened as Parquet.");
            return 0;
        }

        auto file = std::make_shared<OpenedFile>();
        file->path = path;

        std::lock_guard<std::mutex> lock(g_mutex);
        PRQHandle handle = g_next_handle++;
        g_files[handle] = file;
        return handle;
    } catch (const std::exception &error) {
        set_error(error.what());
        return 0;
    }
}

extern "C" char *prq_load_metadata(PRQHandle handle) {
    g_last_error.clear();
    auto file = lookup(handle);
    if (!file) {
        return nullptr;
    }

    try {
        auto reader = parquet::ParquetFileReader::OpenFile(file->path, false);
        auto metadata = reader->metadata();
        std::ostringstream json;
        json << "{";
        json << "\"path\":" << quoted(file->path) << ",";
        json << "\"rowCount\":" << metadata->num_rows() << ",";
        json << "\"columnCount\":" << metadata->num_columns() << ",";
        json << "\"rowGroupCount\":" << metadata->num_row_groups() << ",";
        json << "\"createdBy\":" << quoted(metadata->created_by()) << ",";
        json << "\"rowGroups\":[";
        for (int i = 0; i < metadata->num_row_groups(); ++i) {
            if (i > 0) {
                json << ",";
            }
            auto group = metadata->RowGroup(i);
            json << "{";
            json << "\"index\":" << i << ",";
            json << "\"rowCount\":" << group->num_rows() << ",";
            json << "\"totalByteSize\":" << group->total_byte_size();
            json << "}";
        }
        json << "]}";
        return copy_json(json.str());
    } catch (const std::exception &error) {
        set_error(error.what());
        return nullptr;
    }
}

extern "C" char *prq_load_schema(PRQHandle handle) {
    g_last_error.clear();
    auto file = lookup(handle);
    if (!file) {
        return nullptr;
    }

    try {
        auto reader = parquet::ParquetFileReader::OpenFile(file->path, false);
        auto metadata = reader->metadata();
        auto schema = metadata->schema();
        std::ostringstream json;
        json << "[";
        for (int i = 0; i < schema->num_columns(); ++i) {
            if (i > 0) {
                json << ",";
            }
            auto column = schema->Column(i);
            const bool nullable = column->max_definition_level() > 0;
            json << "{";
            json << "\"index\":" << i << ",";
            json << "\"name\":" << quoted(column->path()->ToDotString()) << ",";
            json << "\"physicalType\":" << quoted(parquet::TypeToString(column->physical_type())) << ",";
            json << "\"logicalType\":" << quoted(column->logical_type()->ToString()) << ",";
            json << "\"nullable\":" << (nullable ? "true" : "false");
            json << "}";
        }
        json << "]";
        return copy_json(json.str());
    } catch (const std::exception &error) {
        set_error(error.what());
        return nullptr;
    }
}

extern "C" char *prq_read_rows(PRQHandle handle, long long offset, int limit, const char *columns_csv) {
    g_last_error.clear();
    auto file = lookup(handle);
    if (!file) {
        return nullptr;
    }
    file->cancelled = false;

    if (offset < 0 || limit <= 0) {
        set_error("Row offset and limit must describe a positive page.");
        return nullptr;
    }

    try {
        auto input_result = arrow::io::ReadableFile::Open(file->path);
        if (!input_result.ok()) {
            set_error(status_message(input_result.status()));
            return nullptr;
        }

        auto open_result = parquet::arrow::OpenFile(*input_result, arrow::default_memory_pool());
        if (!open_result.ok()) {
            set_error(status_message(open_result.status()));
            return nullptr;
        }
        std::unique_ptr<parquet::arrow::FileReader> arrow_reader = std::move(open_result).ValueOrDie();

        auto parquet_metadata = arrow_reader->parquet_reader()->metadata();
        std::vector<int> row_groups;
        row_groups.reserve(parquet_metadata->num_row_groups());
        const long long requested_end = offset + limit;
        long long row_group_base_offset = 0;
        long long cumulative_rows = 0;
        for (int i = 0; i < parquet_metadata->num_row_groups(); ++i) {
            auto row_group = parquet_metadata->RowGroup(i);
            const long long row_group_start = cumulative_rows;
            const long long row_group_end = row_group_start + row_group->num_rows();
            if (row_group_end > offset && row_group_start < requested_end) {
                if (row_groups.empty()) {
                    row_group_base_offset = row_group_start;
                }
                row_groups.push_back(i);
            }
            cumulative_rows = row_group_end;
        }

        auto requested_names = split_columns(columns_csv);
        std::vector<int> column_indices;
        auto schema = parquet_metadata->schema();
        if (!requested_names.empty()) {
            for (const auto &name : requested_names) {
                for (int i = 0; i < schema->num_columns(); ++i) {
                    if (schema->Column(i)->path()->ToDotString() == name) {
                        column_indices.push_back(i);
                        break;
                    }
                }
            }
        } else {
            for (int i = 0; i < schema->num_columns(); ++i) {
                column_indices.push_back(i);
            }
        }

        std::vector<std::string> column_names;
        column_names.reserve(column_indices.size());
        for (int column_index : column_indices) {
            column_names.push_back(schema->Column(column_index)->path()->ToDotString());
        }

        if (row_groups.empty()) {
            std::ostringstream json;
            json << "{";
            json << "\"offset\":" << offset << ",";
            json << "\"limit\":" << limit << ",";
            json << "\"cancelled\":false,";
            json << "\"columns\":[";
            for (size_t i = 0; i < column_names.size(); ++i) {
                if (i > 0) {
                    json << ",";
                }
                json << quoted(column_names[i]);
            }
            json << "],\"rows\":[]}";
            return copy_json(json.str());
        }

        auto batch_reader_result = arrow_reader->GetRecordBatchReader(row_groups, column_indices);
        if (!batch_reader_result.ok()) {
            set_error(status_message(batch_reader_result.status()));
            return nullptr;
        }
        std::unique_ptr<arrow::RecordBatchReader> batch_reader = std::move(batch_reader_result).ValueOrDie();

        long long skipped = row_group_base_offset;
        int emitted = 0;
        std::vector<std::vector<std::string>> rows;

        while (emitted < limit && !file->cancelled) {
            std::shared_ptr<arrow::RecordBatch> batch;
            auto status = batch_reader->ReadNext(&batch);
            if (!status.ok()) {
                set_error(status_message(status));
                return nullptr;
            }
            if (!batch) {
                break;
            }

            if (skipped + batch->num_rows() <= offset) {
                skipped += batch->num_rows();
                continue;
            }

            int64_t start = std::max<int64_t>(0, offset - skipped);
            for (int64_t row = start; row < batch->num_rows() && emitted < limit; ++row) {
                std::vector<std::string> values;
                values.reserve(batch->num_columns());
                for (int col = 0; col < batch->num_columns(); ++col) {
                    auto scalar_result = batch->column(col)->GetScalar(row);
                    if (!scalar_result.ok()) {
                        set_error(status_message(scalar_result.status()));
                        return nullptr;
                    }
                    values.push_back(arrow_scalar_to_string(*scalar_result));
                }
                rows.push_back(values);
                emitted++;
            }
            skipped += batch->num_rows();
        }

        std::ostringstream json;
        json << "{";
        json << "\"offset\":" << offset << ",";
        json << "\"limit\":" << limit << ",";
        json << "\"cancelled\":" << (file->cancelled ? "true" : "false") << ",";
        json << "\"columns\":[";
        for (size_t i = 0; i < column_names.size(); ++i) {
            if (i > 0) {
                json << ",";
            }
            json << quoted(column_names[i]);
        }
        json << "],\"rows\":[";
        for (size_t row = 0; row < rows.size(); ++row) {
            if (row > 0) {
                json << ",";
            }
            json << "[";
            for (size_t col = 0; col < rows[row].size(); ++col) {
                if (col > 0) {
                    json << ",";
                }
                json << quoted(rows[row][col]);
            }
            json << "]";
        }
        json << "]}";
        return copy_json(json.str());
    } catch (const std::exception &error) {
        set_error(error.what());
        return nullptr;
    }
}

extern "C" void prq_cancel(PRQHandle handle) {
    auto file = lookup(handle);
    if (file) {
        file->cancelled = true;
    }
}

extern "C" void prq_close_file(PRQHandle handle) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_files.erase(handle);
}

extern "C" const char *prq_last_error(void) {
    return g_last_error.c_str();
}

extern "C" void prq_free_string(char *value) {
    std::free(value);
}
