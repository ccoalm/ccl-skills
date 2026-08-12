# gRPC `:authority` and DNS-Label Hyphenation

## The quirk

HTTP/2's `:authority` pseudo-header (which carries the host of a gRPC request) is parsed strictly. RFC 1035 says DNS labels can contain letters, digits, and hyphens — but NOT underscores.

Many platforms use PSM-style service names like `<owner>.<class>.<env>`. When any segment contains underscores (e.g. an env segment named `prod_v2` or a feature-flagged variant `payments.ledger.prod_2024`), the SDK puts that name into `:authority`. Envoy / strict gRPC implementations reject the request:

```
RST_STREAM with INTERNAL_ERROR
```

You lose the connection on every call. Frustrating to debug because it looks like network failure.

## Two fixes

### Fix 1 (clean, long-term): forbid underscores in service names

- Naming policy: service name = lowercase, dot-separated segments, hyphens within segments allowed, underscores forbidden.
- Enforce at registry registration (reject the registration).
- Enforce at CI / lint when defining new services.
- Migrate existing names by renaming + parallel registration during a deprecation window.

### Fix 2 (live-system workaround): mesh-level rewrite

When you can't break existing names, an Envoy Lua filter rewrites `:authority` on the fly:

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: modify-grpc-authority
  namespace: istio-system
spec:
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: ANY
        listener:
          filterChain:
            filter:
              name: "envoy.filters.network.http_connection_manager"
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.lua
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
            inlineCode: |
              function envoy_on_request(request_handle)
                local authority = request_handle:headers():get(":authority")
                local content_type = request_handle:headers():get("content-type")
                if authority and content_type and string.find(content_type, "application/grpc") then
                  local modified_authority = string.gsub(authority, "_", "-")
                  request_handle:headers():replace(":authority", modified_authority)
                end
              end
```

Effects:
- Applies to gRPC traffic only (content-type check).
- Rewrites `_` to `-` in `:authority`.
- Callee's registry instance name must also use the `-` form so routing matches.

## When to use which

| Situation | Fix |
|---|---|
| Greenfield platform | Fix 1 — naming policy from day one |
| Mature platform, many existing names | Fix 2 — buy time, then schedule Fix 1 migration |
| Mixed HTTP + gRPC for same service | Fix 2 — HTTP tolerates `_`, gRPC doesn't; rewrite only at gRPC layer |
| Service-mesh-less (direct gRPC) | Fix 1 only — no Envoy to rewrite |

## Verification

Fix 1:
- Registry rejects registration with `_` in name.
- Linter / CI rejects PR adding such a name.

Fix 2:
- Synthetic gRPC call to `<svc>_<env>` → inspect Envoy access log `:authority` field → expect `<svc>-<env>`.
- Callee's access log `host` shows the rewritten form.

## Common variants of the same bug

- HTTP/2 SETTINGS frame rejection on cert SAN mismatch (separate issue, but presents similarly — RST_STREAM with INTERNAL_ERROR).
- gRPC `:scheme` set to `http` while upstream expects `https` (mTLS mismatch).
- IPv6 literal in `:authority` not bracketed.

The Lua rewrite filter is the right tool for the underscore case; do not generalize it to all of the above. Each bug has its own fix.
