#include "commands/model_setup.h"

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/model_ref.h"
#include "commands/commands.h"
#include "io/output.h"
#include "io/proto.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

bool resolve_paths(const std::string& model_id, ResolvedModelPaths* out, std::string* error) {
    v1::ModelLoadRequest request;
    request.set_model_id(model_id);
    const std::string bytes = proto::serialize(request);

    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    v1::ModelLoadResult result;
    if (rac_model_lifecycle_resolve_paths_proto(rac_get_model_registry(),
                                                reinterpret_cast<const uint8_t*>(bytes.data()),
                                                bytes.size(), &out_buffer) != RAC_SUCCESS ||
        !proto::parse_proto_buffer(&out_buffer, &result, error)) {
        return false;
    }
    if (!result.success()) {
        if (error) {
            *error = result.error_message();
        }
        return false;
    }
    out->primary_path = result.resolved_path();
    return true;
}

}  // namespace

bool refresh_registry(std::string* error) {
    v1::ModelRegistryRefreshRequest request;
    request.set_rescan_local(true);
    request.set_include_downloaded_state(true);
    const std::string bytes = proto::serialize(request);

    rac_proto_buffer_t out_buffer;
    rac_proto_buffer_init(&out_buffer);
    if (rac_model_registry_refresh_proto(rac_get_model_registry(),
                                         reinterpret_cast<const uint8_t*>(bytes.data()),
                                         bytes.size(), &out_buffer) != RAC_SUCCESS) {
        rac_proto_buffer_free(&out_buffer);
        if (error) {
            *error = "registry refresh call failed";
        }
        return false;
    }
    v1::ModelRegistryRefreshResult result;
    return proto::parse_proto_buffer(&out_buffer, &result, error);
}

int ensure_model_ready(const GlobalOptions& options, const std::string& ref,
                       ResolvedModelPaths* out) {
    model_ref::Resolved resolved;
    std::string error;
    if (model_ref::resolve(ref, &resolved, &error) != RAC_SUCCESS) {
        out::error_line(error);
        return 1;
    }
    out->model_id = resolved.model_id;

    // Link any on-disk artifacts before deciding whether to pull.
    if (!refresh_registry(&error)) {
        out::status_line("warning: registry refresh failed: " + error);
    }

    // Display name (best effort) + downloaded check.
    bool downloaded = false;
    {
        rac_proto_buffer_t info_out;
        rac_proto_buffer_init(&info_out);
        v1::ModelInfo info;
        if (rac_model_registry_get_proto_buffer(rac_get_model_registry(),
                                                resolved.model_id.c_str(),
                                                &info_out) == RAC_SUCCESS &&
            proto::parse_proto_buffer(&info_out, &info, nullptr)) {
            out->display_name = info.name();
            downloaded = info.is_downloaded() || !info.local_path().empty();
        }
    }

    if (!downloaded) {
        out::status_line("model " + resolved.model_id + " not downloaded — pulling");
        const int pull_code = pull_model_flow(options, resolved.model_id);
        if (pull_code != 0) {
            return pull_code;
        }
    }

    if (!resolve_paths(resolved.model_id, out, &error)) {
        out::error_line("cannot resolve model files for " + resolved.model_id + ": " + error);
        return 1;
    }
    return 0;
}

}  // namespace rcli::commands
