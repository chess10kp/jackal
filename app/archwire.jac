graph layers {
    layer all { *; }
}

graph import {
    plugin_host.pi_shim --> plugin_host.host {
        COMPAT_TIER,
        HOST_CAPS,
        createHostState,
        handleEnvelope,
    }
}

graph import {
    include agent.auth ++> tui.picker_actions {
        load_auth_file,
        save_auth_file,
        resolve_auth_path,
        credential_set,
        stored_api_key,
        get_auth_status,
        transition_auth_flow,
        initial_auth_flow_state,
        format_provider_label,
        oauth_start_login,
    }
    agent.auth_env ++> main { hydrate_auth_environment, logout_provider }
    agent.auth_env ++> tui.commands { logout_provider, stored_providers }
    agent.auth_env ++> tui.picker_actions { hydrate_auth_environment, note_hydrated }
    agent.checkpoints ++> tui.picker_actions {
        create_checkpoint,
        list_checkpoints,
        load_checkpoint,
        restore_checkpoint_files,
        format_checkpoint_overlay_row,
    }
    agent.cli ++> main { parse_cli, user_argv, combine_prompt, CLI_USAGE, CLI_VERSION }
    agent.compaction ++> tui.commands { compute_context_usage }
    agent.context_input ++> tui.context {
        expand_context_input,
        is_valid_file_path,
        parse_line_range,
        _load_file_slice,
    }
    agent.fake_host ++> ui.keybinding_probe { register_fake_shortcut }
    agent.llm ++> tui.overlay { PROVIDER_ROUTES, catalog_models, routed_model_id, provider_for }
    agent.llm ++> tui.picker_actions { PROVIDER_ROUTES, provider_for }
    agent.llm ++> tui.shell { warm_model_catalog }
    agent.modes ++> main { requires_approval, is_read_only_mode, read_only_mode_block_reason }
    agent.modes ++> tui.commands { DEV_MODES }
    agent.modes ++> tui.core { is_read_only_mode }
    include agent.modes ++> tui.input { cycle_mode, is_read_only_mode }
    agent.modes ++> tui.runtime {
        requires_approval,
        is_read_only_mode,
        read_only_mode_block_reason,
    }
    agent.plugin_bridge ++> tui.commands { poll_ui_request, respond_ui, cancel_ui }
    agent.plugin_bridge ++> ui.keybinding_probe { create_bridge, dispose_bridge }
    agent.protocol ++> ui.demo_complex_shell {
        create_adapter,
        make_envelope,
        enqueue,
        dequeue,
        drive_screen,
        cancel_turn,
        queue_stats,
    }
    agent.protocol ++> ui.n1_acceptance { create_adapter, make_envelope, enqueue, drain_and_drive }
    include agent.session ++> main { clear_history }
    include agent.session ++> tui.commands {
        clear_history,
        get_history,
        restore_history,
        list_commands,
        run_command,
        list_extension_shortcuts,
        run_extension_shortcut,
        plugins,
        new_session_id,
        set_model,
        get_model,
        cancel_active_turn,
        compact_now,
        set_mode,
        set_current_session_id,
        mcp_restart,
        mcp_restart_failed,
        mcp_prompt,
        mcp_resources,
        mcp_configured_specs,
    }
    agent.session ++> tui.harness { restore_model, clear_history, set_mode }
    agent.session ++> tui.input {
        cancel_active_turn,
        list_extension_shortcuts,
        run_extension_shortcut,
        set_mode,
    }
    agent.session ++> tui.overlay { get_model, model_preferences }
    agent.session ++> tui.picker_actions { get_history, restore_history, get_model }
    agent.session ++> tui.runtime { run_turn, cancel_active_turn }
    agent.session ++> tui.shell { session_boot, get_model, set_mode, get_mode, drain_mcp_notices }
    agent.session ++> ui.keybinding_probe {
        plugins,
        list_extension_shortcuts,
        run_extension_shortcut,
    }
    agent.session as _session ++> main;
    agent.sessions ++> main {
        list_sessions,
        latest_session_id,
        get_session_record,
        export_session,
        save_session,
        is_valid_session_id,
    }
    agent.sessions ++> tui.commands {
        list_sessions,
        get_session_record,
        export_session,
        save_session,
        is_valid_session_id,
    }
    agent.sessions ++> tui.picker_actions { list_sessions }
    agent.skills ++> tui.commands { load_jackal_skills, expand_skill_command }
    agent.skills ++> tui.context { _load_ignore_rules, _match_ignore_pattern }
    agent.skills ++> tui.picker_actions { load_jackal_skills }
    agent.tasks ++> tui.input { load_tasks, format_tasks_list }
    agent.tasks ++> tui.picker_actions { load_tasks, format_tasks_list, task_counts }
    constraints.algebra ++> ui.layout_compile_emit {
        Constraint,
        Expression,
        Relation,
        StrengthTier,
        Term,
        Variable,
        is_finite,
        normalize_expression,
    }
    constraints.algebra ++> ui.layout_compile_flow { Relation, StrengthTier }
    constraints.algebra ++> ui.layout_compile_model { Variable }
    constraints.algebra ++> ui.layout_compile_overlays { Relation, StrengthTier }
    constraints.algebra ++> ui.layout_compile_relations { Relation, Term }
    include constraints.algebra ++> ui.layout_types { StrengthTier, is_finite }
    include constraints.algebra ++> ui.layout_types_core { StrengthTier, is_finite }
    constraints.solver ++> ui.layout_compile { Solver }
    constraints.solver ++> ui.layout_compile_emit { SolveError }
    constraints.solver ++> ui.layout_compile_model { Solver }
    core.edit ++> agent.tools { apply_edit }
    core.edit ++> tui.overlay { compute_unified_diff }
    tui.format ++> ui.demo_live_shell_messages { format_turn }
    ui.editor ++> tui.input { editor_backspace, editor_history_prev, editor_history_next }
    ui.emulated_terminal ++> e2e.harness { EmulatedTerminal }
    ui.emulated_terminal ++> tui.harness { EmulatedTerminal }
    ui.input ++> tui.input { HostEvent, TextEvent, KeyEvent, PasteEvent, coalesce_events }
    ui.input ++> tui.shell { InputNormalizer }
    ui.input ++> tui.state { InputNormalizer }
    ui.layout ++> tui.core { LayoutSpec, fill_axis, fixed_axis }
    ui.layout ++> tui.overlay { LayoutSpec, OverlayAnchor, fill_axis, fixed_axis }
    ui.model ++> tui.overlay { UiNode }
    ui.renderer ++> tui.core { set_node_contract }
    ui.renderer ++> tui.overlay {
        render_frame,
        set_node_content,
        set_node_contract,
        mark_semantic_dirty,
        mark_layout_dirty,
        request_cursor,
    }
    ui.renderer ++> tui.runtime { create_renderer }
    ui.renderer ++> tui.shell { create_renderer }
    ui.renderer ++> tui.state { Renderer }
    ui.runtime ++> tui.shell { create_session, dispose_session }
    ui.runtime ++> tui.state { UiSession }
    ui.screen ++> agent.protocol { ShellScreen }
    ui.screen ++> tui.core { configure_main_shell_layout }
    ui.screen ++> tui.input { shell_insert_text, shell_submit, shell_cancel }
    ui.screen ++> tui.runtime { shell_resize }
    ui.screen ++> tui.shell { build_main_shell, install_shell_contracts }
    ui.screen ++> tui.state { ShellScreen }
    ui.screen ++> tui.windows { shell_open_approval, shell_close_approval }
    ui.terminal ++> tui.shell { Terminal, ProcessTerminal, read_terminal_size }
    ui.terminal ++> tui.state { Terminal }
    ui.transcript ++> tui.commands { apply_transcript_revision }
    ui.transcript ++> tui.core {
        TranscriptMessage,
        apply_transcript_revision,
        measure_message_height,
        set_follow_tail,
    }
    ui.transcript ++> tui.input { set_follow_tail }
    ui.transcript ++> tui.overlay { materialize_visible }
    ui.transcript ++> tui.picker_actions { apply_transcript_revision }
    ui.transcript ++> tui.shell { bind_transcript, set_follow_tail }
    ui.transcript ++> tui.state { TranscriptProjection, TranscriptMessage }
    ui.width ++> tui.core { display_width, truncate_text }
    ui.width ++> tui.overlay { display_width, truncate_text }
    ui.width ++> tui.window { display_width, truncate_text }
}

graph import agent {
    agent_tools ++> session_lifecycle { register_agent_tools }
    auth ++> auth_env {
        load_auth_file,
        save_auth_file,
        resolve_auth_path,
        stored_api_key,
        credential_remove,
        has_credential,
    }
    include auth_credentials ++> auth {
        AUTH_FILE_NAME,
        DEFAULT_AGENT_DIR_NAME,
        KNOWN_AUTH_TYPES,
        OAUTH_REQUIRED_KEYS,
        _path_abspath,
        _path_expanduser,
        _path_dirname,
        _file_chmod,
        resolve_auth_path,
        load_auth_file,
        save_auth_file,
        validate_credential,
        credential_get,
        credential_set,
        credential_remove,
        has_credential,
        now_ms,
        is_expired,
        stored_api_key,
        get_auth_status,
    }
    auth_credentials ++> auth_display { KNOWN_AUTH_TYPES }
    include auth_credentials ++> auth_flow { KNOWN_AUTH_TYPES }
    include auth_display ++> auth {
        redact_secret,
        redact_credential,
        validate_provider_entry,
        login_kind,
        needs_oauth,
        validate_model_entry,
        filter_providers_by_query,
        filter_models_by_query,
        format_provider_label,
        format_model_label,
    }
    auth_display ++> auth_flow { validate_provider_entry, validate_model_entry }
    include auth_flow ++> auth { initial_auth_flow_state, step_is_pending, transition_auth_flow }
    include auth_network ++> auth { oauth_refresh_credentials, oauth_start_login }
    include compaction ++> session {
        load_project_config,
        resolve_auto_compact_config,
        compute_context_usage,
        should_auto_compact,
        build_mechanical_summary,
        summarize_for_compaction,
    }
    compaction ++> session_config { load_project_config }
    compaction ++> session_turn {
        load_project_config,
        resolve_auto_compact_config,
        compute_context_usage,
        should_auto_compact,
        build_mechanical_summary,
        summarize_for_compaction,
    }
    compaction ++> subagents { load_project_config }
    include extensions ++> session {
        ExtensionDecl,
        ExtensionStatus,
        load_extension_decls,
        node_sidecar_decls,
        extensions_label,
        resolve_decl_path,
        decl_from_dict,
    }
    extensions ++> session_lifecycle {
        ExtensionDecl,
        ExtensionStatus,
        load_extension_decls,
        node_sidecar_decls,
        extensions_label,
        resolve_decl_path,
        decl_from_dict,
    }
    include fake_host ++> plugin_bridge {
        FakePluginHost,
        FakeUi,
        apply_hello,
        create_fake_host,
        ensure_host,
        touch_bridge,
    }
    fake_host ++> plugin_bridge_core { FakePluginHost, ensure_host, touch_bridge }
    fake_host ++> plugin_bridge_extensions { FakeUi, ensure_host, touch_bridge }
    include fake_host ++> plugin_bridge_features { FakePluginHost, touch_bridge }
    include fake_host ++> plugin_bridge_hooks { FakePluginHost, FakeUi, touch_bridge }
    include fake_host ++> plugin_bridge_host { ensure_host, touch_bridge, apply_hello }
    fake_host ++> plugin_bridge_traffic { FakePluginHost }
    include fake_host ++> plugin_hooks_events { register_fake_listener }
    include fake_host_types ++> fake_host {
        FAKE_HOST_CAPS,
        FAKE_COMPAT_TIER,
        FakePluginHost,
        create_fake_host,
    }
    include interactions ++> plugin_bridge { new_ui_queue, UiInteractionQueue }
    interactions ++> plugin_bridge_io { new_ui_queue, UiInteractionQueue }
    interactions ++> plugin_bridge_ui { UiInteractionQueue }
    json_pretty ++> auth_credentials { json_pretty }
    json_pretty ++> checkpoints { json_pretty }
    json_pretty ++> session_config { json_pretty }
    json_pretty ++> sessions_core { json_pretty }
    json_pretty ++> tasks { json_pretty }
    llm ++> agent_tools { react_loop, make_transport, credential_error }
    llm ++> auth_env { PROVIDER_ROUTES }
    llm ++> compaction { make_transport }
    include llm ++> session {
        Transport,
        react_loop,
        make_transport,
        make_ext_transport,
        TurnCancel,
        provider_for,
        credential_error,
    }
    llm ++> session_config { provider_for, credential_error }
    llm ++> session_turn { react_loop, make_transport, make_ext_transport, TurnCancel }
    include llm_loop ++> llm {
        ToolSpec,
        MAX_TOOL_RESULT,
        ToolRegistry,
        TurnCancel,
        react_loop,
        _tool_defs,
        _find_spec,
        _is_transient_error,
        _cap_tool_result,
        _notify_message_end,
    }
    include llm_transport ++> llm {
        Transport,
        ProviderTransport,
        PluginBridge,
        PROVIDER_ROUTES,
        provider_for,
        credential_error,
        routed_model_id,
        make_transport,
        make_ext_transport,
    }
    llm_transport ++> llm_loop { Transport }
    llm_transport ++> model_catalog { PROVIDER_ROUTES }
    logging ++> checkpoints { log_debug, log_warn, log_exception }
    logging ++> registry { log_exception }
    include mcp ++> session { McpClient, create_mcp_client, mcp_start, mcp_list_tools, mcp_stop }
    mcp ++> session_config {
        McpClient,
        create_mcp_client,
        mcp_start,
        mcp_start_http,
        mcp_list_tools,
        mcp_stop,
        mcp_drain_notifications,
        mcp_is_alive,
        mcp_get_prompt,
        mcp_list_resources,
        mcp_read_resource,
    }
    include mcp ++> session_lifecycle { McpClient, mcp_stop }
    mcp ++> session_state { McpClient }
    include model_catalog ++> llm { catalog_models, warm_model_catalog, refresh_model_catalog }
    modes ++> agent_tools {
        requires_approval,
        is_read_only_mode,
        is_tool_blocked,
        read_only_mode_block_reason,
        READ_ONLY_TOOLS,
    }
    modes ++> approvals { requires_approval }
    modes ++> cli { DEV_MODES }
    include modes ++> session { DEV_MODES, system_prompt_for_mode }
    modes ++> session_config {
        DEV_MODES,
        register_mcp_read_only_tools,
        unregister_mcp_read_only_tools,
    }
    modes ++> session_turn { system_prompt_for_mode }
    plugin_bridge ++> llm_loop {
        PluginBridge,
        context_gate,
        fire_hook,
        tool_call_gate,
        tool_result_gate,
    }
    include plugin_bridge ++> llm_transport {
        PluginBridge,
        context_gate,
        fire_hook,
        prepare_provider_request,
        resolve_ext_model,
        tool_call_gate,
        tool_result_gate,
    }
    include plugin_bridge ++> plugin_hooks_events {
        create_bridge,
        ensure_node_host,
        load_extension_path,
        dispose_bridge,
        fire_hook,
        fire_user_bash,
        fire_project_trust,
        PluginBridge,
    }
    include plugin_bridge ++> session {
        PluginBridge,
        create_bridge,
        dispose_bridge,
        host_status,
        ensure_node_host,
        load_extension_path,
        invoke_command,
        invoke_shortcut,
        fire_user_bash,
        fire_hook,
        transform_markdown,
        drain_extension_traffic,
        agent_start_gate,
        input_gate,
        render_extension_block,
        list_shortcuts,
        list_labels,
        drain_model_requests,
        fire_project_trust,
    }
    plugin_bridge ++> session_commands {
        PluginBridge,
        invoke_command,
        invoke_shortcut,
        list_shortcuts,
        list_labels,
    }
    plugin_bridge ++> session_config { PluginBridge, fire_hook, drain_model_requests }
    plugin_bridge ++> session_lifecycle {
        PluginBridge,
        create_bridge,
        dispose_bridge,
        host_status,
        ensure_node_host,
        load_extension_path,
        fire_hook,
        fire_user_bash,
        fire_project_trust,
    }
    plugin_bridge ++> session_state { PluginBridge }
    include plugin_bridge ++> session_turn {
        PluginBridge,
        input_gate,
        agent_start_gate,
        fire_hook,
        drain_extension_traffic,
        transform_markdown,
        render_extension_block,
        drain_model_requests,
    }
    include plugin_bridge_core ++> plugin_bridge {
        PluginBridge,
        create_bridge,
        _alloc_corr,
        _node_alive,
        _emit_host_status,
        invoke_tool,
        _invoke_tool_fake,
        _invoke_tool_node,
    }
    plugin_bridge_core ++> plugin_bridge_extensions {
        PluginBridge,
        _alloc_corr,
        _node_alive,
        _emit_host_status,
    }
    plugin_bridge_core ++> plugin_bridge_features { PluginBridge, _alloc_corr, _node_alive }
    plugin_bridge_core ++> plugin_bridge_hooks { PluginBridge, _alloc_corr, _node_alive }
    plugin_bridge_core ++> plugin_bridge_ui { PluginBridge }
    include plugin_bridge_extensions ++> plugin_bridge {
        load_extension,
        caps_satisfied,
        ui_cap_satisfied,
        load_extension_path,
        unload_extension,
        invoke_shortcut,
        cancel_tool,
        drain_inbox,
        invoke_command,
    }
    include plugin_bridge_features ++> plugin_bridge {
        transform_markdown,
        drain_extension_traffic,
        set_session_name,
        resolve_ext_model,
        prepare_provider_request,
        _fake_content_lines,
        render_extension_block,
    }
    include plugin_bridge_hooks ++> plugin_bridge {
        fire_hook_data,
        _absorb_hook_results,
        _ok_verdicts,
        tool_call_gate,
        tool_result_gate,
        input_gate,
        context_gate,
        agent_start_gate,
        fire_hook,
        fire_user_bash,
        fire_project_trust,
    }
    plugin_bridge_hooks ++> plugin_bridge_features { fire_hook_data, _ok_verdicts }
    include plugin_bridge_host ++> plugin_bridge {
        host_status,
        maybe_reap_idle,
        ensure_node_host,
        maybe_restart_host,
        dispose_bridge,
    }
    plugin_bridge_host ++> plugin_bridge_core { maybe_restart_host, host_status }
    plugin_bridge_host ++> plugin_bridge_extensions {
        ensure_node_host,
        maybe_restart_host,
        host_status,
    }
    include plugin_bridge_io ++> plugin_bridge {
        _write_node,
        _dispatch_inbound,
        _reader_loop,
        _ensure_io,
        _start_reader,
        _stop_reader,
        _prepare_corr,
        _wait_corr,
        _read_node,
        _read_node_until,
        _ui_queue,
        _ui_enqueue_from_env,
        _ui_send_response,
    }
    plugin_bridge_io ++> plugin_bridge_core { _write_node, _prepare_corr, _read_node_until }
    plugin_bridge_io ++> plugin_bridge_extensions { _write_node, _prepare_corr, _read_node_until }
    plugin_bridge_io ++> plugin_bridge_features { _write_node, _prepare_corr, _read_node_until }
    plugin_bridge_io ++> plugin_bridge_hooks { _write_node, _prepare_corr, _read_node_until }
    plugin_bridge_io ++> plugin_bridge_host {
        _ensure_io,
        _start_reader,
        _stop_reader,
        _read_node_until,
        _write_node,
    }
    include plugin_bridge_io ++> plugin_bridge_ui { _ui_queue, _ui_send_response }
    include plugin_bridge_support ++> plugin_bridge {
        _path_abspath,
        _path_dirname,
        resolve_host_mjs,
        resolve_stub_echo,
        resolve_pi_greet,
        resolve_pi_ctx_probe,
        resolve_stub_commands,
        resolve_pi_gated,
        resolve_node_bin,
        envelope_to_dict,
        envelope_from_dict,
    }
    plugin_bridge_support ++> plugin_bridge_extensions { _path_abspath }
    plugin_bridge_support ++> plugin_bridge_host { resolve_host_mjs, resolve_node_bin }
    plugin_bridge_support ++> plugin_bridge_io { envelope_to_dict, envelope_from_dict }
    include plugin_bridge_traffic ++> plugin_bridge {
        _absorb_payload,
        list_shortcuts,
        list_labels,
        drain_model_requests,
        _absorb_pending_fake,
    }
    plugin_bridge_traffic ++> plugin_bridge_core { _absorb_payload }
    plugin_bridge_traffic ++> plugin_bridge_extensions { _absorb_payload, _absorb_pending_fake }
    plugin_bridge_traffic ++> plugin_bridge_features { _absorb_payload, _absorb_pending_fake }
    plugin_bridge_traffic ++> plugin_bridge_hooks { _absorb_payload, _absorb_pending_fake }
    include plugin_bridge_ui ++> plugin_bridge {
        poll_ui_request,
        respond_ui,
        cancel_ui,
        cancel_all_ui,
    }
    protocol ++> fake_host { Envelope, make_envelope }
    include protocol ++> plugin_bridge { Envelope, make_envelope, is_plugin_kind }
    protocol ++> plugin_bridge_core { Envelope, make_envelope }
    include protocol ++> plugin_bridge_extensions { Envelope, make_envelope, is_plugin_kind }
    include protocol ++> plugin_bridge_features { Envelope, make_envelope }
    include protocol ++> plugin_bridge_hooks { Envelope, make_envelope }
    include protocol ++> plugin_bridge_host { Envelope, make_envelope }
    include protocol ++> plugin_bridge_io { Envelope, make_envelope, is_plugin_kind }
    protocol ++> plugin_bridge_support { Envelope, make_envelope }
    registry ++> agent_tools { ToolRegistry, register_native_spec, create_registry, get_tool }
    registry ++> llm_loop { ToolRegistry, as_tool_specs, invoke }
    include registry ++> llm_transport { ToolRegistry, as_tool_specs, invoke }
    include registry ++> plugin_bridge { ToolRegistry, register_js, unregister_extension }
    registry ++> plugin_bridge_extensions { ToolRegistry, register_js, unregister_extension }
    include registry ++> plugin_hooks_events { create_registry }
    include registry ++> session { ToolRegistry, register_native, get_tool }
    registry ++> session_config { ToolRegistry, register_native, unregister, get_tool }
    registry ++> session_lifecycle { get_tool }
    registry ++> tools { ToolRegistry, create_registry, register_native_spec }
    include session_commands ++> session {
        get_history,
        restore_history,
        set_current_session_id,
        cancel_active_turn,
        list_commands,
        run_command,
        run_extension_shortcut,
        list_extension_shortcuts,
        list_extension_labels,
        json_event,
    }
    include session_config ++> session {
        set_mode,
        get_mode,
        model_preferences,
        set_model as _set_model,
        set_thinking_level as _set_thinking_level,
        clear_history,
        mcp_restart,
        mcp_restart_failed,
        mcp_prompt,
        mcp_resources,
        mcp_configured_specs,
        mcp_status_lines,
        mcp_server_specs,
        drain_mcp_notices,
    }
    session_config ++> session_commands { _apply_pending_model_requests }
    session_config ++> session_lifecycle { set_mode, _attach_mcp_servers, _load_model_prefs }
    include session_config ++> session_turn {
        set_model,
        set_thinking_level,
        _apply_pending_model_requests,
        wait_mcp_ready,
    }
    include session_lifecycle ++> session {
        session_boot,
        wait_extensions_ready,
        enqueue_prompt,
        drain_prompt_queue,
        session_dispose,
        extensions_status,
    }
    session_lifecycle ++> session_turn { session_boot, wait_extensions_ready }
    session_state ++> agent_tools {
        plugins,
        get_model_state,
        get_thinking_level_state,
        get_mode_state,
    }
    include session_state ++> session {
        SessionPlugins,
        history,
        show_stats,
        mode,
        plugins,
        get_model_state,
        get_thinking_level_state,
        set_model_state,
    }
    session_state ++> session_commands { history, plugins }
    include session_state ++> session_config {
        history,
        model,
        thinking_level,
        mode,
        plugins,
        _model_prefs,
        _model_prefs_loaded,
        set_mode_state,
        get_mode_state,
        set_model_state,
        get_model_state,
        set_thinking_level_state,
        get_thinking_level_state,
        adopt_model_prefs,
    }
    session_state ++> session_lifecycle { plugins }
    session_state ++> session_turn {
        history,
        show_stats,
        plugins,
        _t0,
        _n_tools,
        reset_turn_stats,
        bump_tool_count,
        get_model_state,
        get_thinking_level_state,
        get_mode_state,
    }
    include session_turn ++> session {
        render_event,
        relay_tool_hooks,
        run_turn,
        _apply_extension_traffic,
        compact_now,
    }
    include sessions ++> session {
        save_session,
        list_sessions,
        latest_session_id,
        get_session_record,
        export_session,
        new_session_id,
        is_valid_session_id,
    }
    sessions ++> session_commands { new_session_id }
    sessions ++> session_turn { save_session, new_session_id, is_valid_session_id }
    include sessions_core ++> sessions {
        _last_id_ms,
        _SESSION_ID_PATTERN,
        _DEFAULT_NAME,
        _INDEX_NAME,
        _LEGACY_INDEX_NAME,
        _TRANSCRIPT_SUFFIX,
        _path_abspath,
        _path_dirname,
        _sessions_dir,
        _session_path,
        _index_path,
        is_valid_session_id,
        _next_epoch_ms,
        new_session_id,
        _iso_from_ms,
        _now_iso,
        _read_json,
        _write_json,
        _is_record,
        _is_index_entry,
        _entry_sort_key,
        _newest_first,
        _read_index,
        _write_index,
        _upsert_index_entry,
        _scan_directory,
        save_session,
        get_session_record,
        load_session,
        list_sessions,
        rename_session,
        delete_session,
    }
    include sessions_core ++> sessions_maintenance {
        _path_abspath,
        _path_dirname,
        _sessions_dir,
        _session_path,
        _read_json,
        _write_json,
        _write_index,
        get_session_record,
        list_sessions,
    }
    include sessions_maintenance ++> sessions {
        _iso_to_epoch,
        prune_sessions,
        latest_session_id,
        export_session,
    }
    include skills_discovery ++> skills {
        _load_skills_from_dir,
        load_skills_from_dir,
        _find_project_skills_dir,
        _normalize_path,
        _resolve_skill_path,
        _path_under,
        _get_source,
        _add_loaded,
        _resolve_package_root,
        _skill_sort_key,
        load_jackal_skills,
    }
    include skills_support ++> skills {
        MAX_NAME_LENGTH,
        MAX_DESCRIPTION_LENGTH,
        IGNORE_FILE_NAMES,
        _base_name,
        _dir_name,
        _rel_path,
        _abs_path,
        _canonical,
        _is_abs,
        _user_home,
        _parse_scalar,
        parse_frontmatter,
        frontmatter_string,
        _gitignore_parse_rules,
        _load_ignore_rules,
        _match_ignore_pattern,
        _validate_name,
        _validate_description,
        _warning,
        _load_skill_from_file,
    }
    include skills_support ++> skills_discovery {
        _abs_path,
        _base_name,
        _canonical,
        _dir_name,
        _load_ignore_rules,
        _load_skill_from_file,
        _match_ignore_pattern,
        _rel_path,
        _user_home,
        _is_abs,
        _warning,
    }
    subagents ++> agent_tools {
        list_subagents,
        get_subagent,
        EXCLUDED_SUBAGENT_TOOLS,
        load_project_model_overrides,
    }
    subagents ++> chains { resolve_jackal_root, frontmatter_string, parse_frontmatter, _abs_path }
    system ++> agent_tools { SYSTEM_PROMPT }
    include system ++> session { SYSTEM_PROMPT }
    system ++> session_turn { SYSTEM_PROMPT }
    tasks ++> agent_tools {
        load_tasks,
        add_task,
        update_tasks,
        remove_task_by_id,
        format_tasks_list,
    }
    tool_spec ++> agent_tools { make_tool_spec, ToolSpec }
    tool_spec ++> llm_loop { ToolSpec, MAX_TOOL_RESULT }
    include tool_spec ++> llm_transport { ToolSpec, MAX_TOOL_RESULT }
    tool_spec ++> registry { ToolSpec, make_tool_spec }
    tool_spec ++> tools { ToolSpec, make_tool_spec, MAX_TOOL_RESULT, MAX_SEARCH_RESULTS }
    tool_spec ++> web_tools { MAX_TOOL_RESULT }
    include tools ++> session { default_registry }
    tools ++> session_lifecycle { default_registry }
    tools ++> session_turn { default_registry }
    web_tools ++> tools { _web_search_tool, _web_fetch_tool }
}

graph import constraints {
    algebra ++> layout_relations {
        Constraint,
        Expression,
        Relation,
        StrengthTier,
        Term,
        Variable,
        normalize_expression,
    }
    algebra ++> oracle_driver {
        Constraint,
        Expression,
        Relation,
        StrengthTier,
        Term,
        Variable,
        add_expressions,
    }
    include algebra ++> solver {
        EPSILON,
        Constraint,
        Expression,
        LexWeight,
        Relation,
        StrengthTier,
        Term,
        Variable,
        constraint_key,
        is_finite,
        lex_add,
        lex_compare,
        lex_is_negative,
        lex_is_zero,
        lex_neg,
        lex_scale,
        lex_zero,
        near_zero,
        normalize_expression,
        strength_weight,
        term,
    }
    include algebra ++> solver_types {
        EPSILON,
        Constraint,
        Expression,
        LexWeight,
        Relation,
        StrengthTier,
        Term,
        Variable,
        constraint_key,
        is_finite,
        lex_add,
        lex_compare,
        lex_is_negative,
        lex_is_zero,
        lex_neg,
        lex_scale,
        lex_zero,
        near_zero,
        normalize_expression,
        strength_weight,
        term,
    }
    include results ++> oracle_driver { SolveError }
    results ++> solver { ConstraintHandle, SolveError, SolveResult, SolverSnapshot }
    include results ++> solver_types { ConstraintHandle, SolveError, SolveResult, SolverSnapshot }
    solver ++> oracle_driver { Solver }
    solver_types ++> solver {
        SymbolKind,
        MutationJournal,
        Tag,
        Row,
        CostRow,
        StoredConstraint,
        EditInfo,
    }
}

graph import e2e {
    include harness ++> integrations {
        make_sandbox,
        run_jackal,
        jsonl,
        fixture_path,
        write_project_config,
        RunResult,
    }
    include harness ++> json_protocol {
        make_sandbox,
        run_jackal,
        jsonl,
        spawn_tui,
        TuiSession,
        RunResult,
    }
    include harness ++> print_mode {
        make_sandbox,
        run_jackal,
        jsonl,
        spawn_tui,
        TuiSession,
        RunResult,
    }
    include harness ++> repl { make_sandbox, run_jackal, jsonl, spawn_tui, TuiSession, RunResult }
    include harness ++> tui { make_sandbox, run_jackal, jsonl, spawn_tui, TuiSession, RunResult }
}

graph import tui {
    commands ++> input { _resume_session, _handle_ui_modal_key, _tick_ui_modal, _run_slash }
    context ++> commands { _open_explorer_picker }
    context ++> input { _format_mentions, _expand_quoted_context, _insert_into_draft }
    context ++> picker_actions { _skills_picker_entries }
    core ++> commands { _push_turn }
    core ++> input { _push_turn, _scroll_transcript }
    include core ++> overlay { _rule, _pad_to, _prompt_prefix, _prompt_lines }
    core ++> picker_actions { _push_turn, _meter }
    core ++> runtime { _push_turn, _rewrite_turn, _finish_turn, _install_layout }
    core ++> shell { _push_turn, _install_layout }
    core ++> windows { _push_turn }
    format ++> core { format_turn }
    format ++> runtime { format_tool_call, format_tool_result }
    input ++> shell { _tick_app, _handle_host_events }
    mcp ++> commands { _mcp_window_state }
    overlay ++> input { _slash_popup_state, _slash_popup_pick }
    overlay ++> shell { _render }
    picker_actions ++> commands {
        _open_login_picker,
        _open_resume_picker,
        _open_tasks_picker,
        _open_checkpoints_picker,
        _create_checkpoint_now,
        _open_skills_picker,
    }
    picker_actions ++> input { _complete_api_key_login, _start_login_provider, _cancel_login }
    picker_actions ++> input { _restore_checkpoint }
    picker_actions ++> shell { _hydrate_auth_environment }
    picker_base ++> commands { _open_picker }
    picker_base ++> context { _open_picker }
    picker_base ++> input { _close_picker, _multi_filtered }
    picker_base ++> overlay { _picker_filtered }
    picker_base ++> picker_actions { _open_picker, _close_picker }
    preview ++> runtime { tool_result_preview }
    runtime ++> commands { _begin_assistant_reply }
    include runtime ++> input {
        _begin_assistant_reply,
        _finish_stream,
        _tick_stream,
        _accept_approval,
        _reject_approval,
    }
    runtime ++> shell { _apply_resize }
    shell ++> harness { boot_tui, tui_step, shutdown_tui }
    state ++> commands { LiveShell, SLASH_BUILTINS }
    state ++> context {
        LiveShell,
        _QUOTED_MENTION_PATTERN,
        _EXPLORER_SKIP_DIRS,
        _EXPLORER_MAX_FILES,
        _EXPLORER_MAX_DEPTH,
    }
    state ++> core { LiveShell }
    state ++> harness { LiveShell }
    state ++> input { LiveShell }
    state ++> overlay { LiveShell }
    state ++> picker_actions { LiveShell }
    state ++> picker_base { LiveShell }
    state ++> runtime { LiveShell }
    state ++> shell { LiveShell }
    state ++> windows { LiveShell }
    window ++> commands { WindowSpec, WindowState }
    include window ++> mcp { WindowSpec, WindowState, window_lines }
    window ++> overlay { WindowSpec, window_frame, window_view }
    window ++> picker_base { WindowSpec, WindowState }
    window ++> runtime { WindowSpec, WindowState }
    window ++> state { WindowState }
    window ++> windows { WindowState, window_lines }
    windows ++> commands { _picker_state, _ui_modal_state, _close_top_window, _open_window }
    windows ++> input { _picker_state, _handle_window_key, _ui_modal_state }
    windows ++> overlay { _picker_state, _window_paint_lines, _ui_modal_state, _approval_state }
    windows ++> picker_actions { _picker_state }
    windows ++> picker_base { _open_window, _close_top_window, _picker_state, _ui_modal_state }
    windows ++> runtime { _open_window, _close_top_window, _approval_state }
}

graph import ui {
    bindings ++> demo_complex_shell { is_empty }
    bindings ++> gates { is_empty }
    bindings ++> inspect { Binding }
    include bindings ++> runtime { BindingRegistry, clear_bindings, find_orphan_bindings, is_empty }
    include bindings ++> runtime_core {
        BindingRegistry,
        clear_bindings,
        find_orphan_bindings,
        is_empty,
    }
    bindings ++> screen { subscribe }
    cells ++> markdown_proj { StyleAttrs }
    include cells ++> renderer {
        CellBuffer,
        StyleAttrs,
        StyledCell,
        create_buffer,
        buffer_clear_rect,
        buffer_blit_text,
        buffer_to_plain_rows,
        diff_buffers_ansi,
    }
    cells ++> renderer_damage { CellBuffer, diff_buffers_ansi }
    cells ++> renderer_paint {
        CellBuffer,
        StyleAttrs,
        create_buffer,
        buffer_clear_rect,
        buffer_blit_text,
    }
    cells ++> renderer_types { CellBuffer }
    demo_complex_shell_render ++> demo_complex_shell { _install_shell_layout, _paint_shell }
    demo_live_shell_messages ++> demo_live_shell { _push_turn, _rewrite_turn }
    demo_live_shell_model ++> demo_live_shell { LiveShell, make_live_shell }
    demo_live_shell_model ++> demo_live_shell_messages { LiveShell }
    demo_live_shell_model ++> demo_live_shell_render { LiveShell }
    demo_live_shell_render ++> demo_live_shell { _install_layout, _render }
    editor ++> demo_live_shell { editor_backspace, editor_history_prev, editor_history_next }
    editor ++> screen { editor_insert, editor_submit, AblePrompt }
    events ++> editor { InsertText, Submit, Cancel, SendPrompt }
    events ++> gates { InsertText, dispatch_event }
    events ++> inspect { UiEvent, containment_path, resolve_target }
    events ++> screen { SendPrompt, InsertText, Submit, Cancel, dispatch_event }
    host ++> n1_acceptance {
        create_host_loop,
        run_host_tick,
        note_interrupt,
        host_events_to_effects,
    }
    input ++> demo_live_shell {
        HostEvent,
        InputNormalizer,
        TextEvent,
        KeyEvent,
        PasteEvent,
        coalesce_events,
    }
    input ++> host {
        HostEvent,
        InputNormalizer,
        KeyEvent,
        EofEvent,
        InterruptEvent,
        coalesce_events,
    }
    input ++> n1_acceptance { InputNormalizer, KeyEvent }
    include input_events ++> input {
        ESC,
        BRACKETED_PASTE_START,
        BRACKETED_PASTE_END,
        HostEvent,
        TextEvent,
        KeyEvent,
        PasteEvent,
        ResizeEvent,
        MouseEvent,
        StreamChunkEvent,
        EofEvent,
        InterruptEvent,
    }
    input_events ++> input_sequences { ESC, HostEvent, TextEvent, KeyEvent, MouseEvent }
    include input_sequences ++> input {
        sequence_status,
        extract_sequences,
        decode_sequence,
        LEGACY_KEYS,
        MODIFIER_NAMES,
        CSI_LETTER_KEYS,
    }
    inspect ++> demo_complex_shell {
        validate_invariants,
        dump_graph,
        dump_bindings,
        dump_lifetimes,
    }
    inspect ++> gates { validate_invariants }
    include layout ++> renderer { compute_layout }
    layout ++> renderer_damage { compute_layout }
    layout_compile ++> layout {
        CompileResult,
        PartitionInfo,
        collect_scope_for_engine,
        compile_scoped_layout,
    }
    layout_compile_emit ++> layout_compile { _emit_invariants, _emit_root, _req }
    layout_compile_emit ++> layout_compile_flow {
        _axis_end,
        _axis_start,
        _emit,
        _emit_cross_axis,
        _emit_sized_axis,
        _expr,
        _prov,
        _req,
        _t,
    }
    include layout_compile_emit ++> layout_compile_overlays {
        _emit,
        _emit_sized_axis,
        _expr,
        _prov,
        _req,
        _t,
    }
    layout_compile_emit ++> layout_compile_relations { _emit, _expr, _t }
    layout_compile_flow ++> layout_compile { _emit_partition }
    layout_compile_model ++> layout { _ScopedNode }
    include layout_compile_model ++> layout_compile {
        CompileResult,
        NodeEdges,
        PartitionInfo,
        _Entry,
        _Scope,
    }
    layout_compile_model ++> layout_compile_emit { CompileResult, NodeEdges, _Entry, _wants }
    include layout_compile_model ++> layout_compile_flow {
        CompileResult,
        NodeEdges,
        PartitionInfo,
        _Allocation,
        _Entry,
        _FlowChild,
        _wants,
    }
    layout_compile_model ++> layout_compile_overlays { CompileResult, NodeEdges, _Entry, _wants }
    layout_compile_model ++> layout_compile_relations { CompileResult, NodeEdges, _wants }
    layout_compile_model ++> layout_compile_scope { _Scope, _ScopedNode }
    layout_compile_overlays ++> layout_compile { _emit_overlay }
    layout_compile_relations ++> layout_compile { _emit_relation }
    layout_compile_scope ++> layout_compile { _collect_scope }
    include layout_measure ++> layout {
        natural_width,
        wrapped_lines_at,
        invalidate_measurement_cache,
    }
    layout_measure ++> layout_types { invalidate_measurement_cache }
    layout_quantize ++> layout { PartitionRequest, quantize_partition, snap_edge }
    layout_types ++> cells { Rect }
    include layout_types ++> demo_complex_shell { LayoutSpec, fill_axis, fixed_axis, grow_axis }
    layout_types ++> demo_complex_shell_render { LayoutSpec, fill_axis, fixed_axis, grow_axis }
    include layout_types ++> demo_live_shell { LayoutSpec, fill_axis, fixed_axis, grow_axis }
    layout_types ++> demo_live_shell_render { LayoutSpec, fill_axis, fixed_axis, grow_axis }
    include layout_types ++> layout {
        Align,
        Axis,
        AxisSize,
        ContentEntry,
        FrameEntry,
        LayoutDiagnostic,
        LayoutError,
        LayoutFrame,
        LayoutRelation,
        LayoutRelationKind,
        LayoutResult,
        LayoutSeverity,
        LayoutSpec,
        LayoutState,
        MeasureEntry,
        MutationResult,
        OverlayAnchor,
        Rect,
        RelationHandle,
        Size,
        SizeMode,
        Viewport,
        rect_union,
        fill_axis,
        fixed_axis,
        grow_axis,
        intrinsic_axis,
        create_layout_state,
        validate_spec,
        set_spec,
        add_relation,
        remove_relation,
        set_content,
        set_scroll_offset,
        clear_node,
        frame_entry_of,
        rect_of,
        _copy_rect,
    }
    layout_types ++> layout_compile {
        LayoutDiagnostic,
        LayoutError,
        LayoutSeverity,
        LayoutState,
        Size,
        SizeMode,
        Viewport,
    }
    include layout_types ++> layout_compile_emit {
        Align,
        AxisSize,
        LayoutDiagnostic,
        LayoutError,
        LayoutRelation,
        LayoutSeverity,
        LayoutSpec,
        OverlayAnchor,
        Size,
        SizeMode,
        Viewport,
    }
    layout_types ++> layout_compile_flow {
        AxisSize,
        LayoutDiagnostic,
        LayoutError,
        LayoutSeverity,
        Size,
        SizeMode,
    }
    include layout_types ++> layout_compile_model { AxisSize, LayoutDiagnostic, LayoutSpec, Size }
    include layout_types ++> layout_compile_overlays {
        LayoutDiagnostic,
        LayoutSpec,
        OverlayAnchor,
        Size,
        SizeMode,
    }
    layout_types ++> layout_compile_relations { LayoutRelation, LayoutRelationKind }
    layout_types ++> layout_compile_scope { LayoutDiagnostic, LayoutError, LayoutSeverity }
    layout_types ++> layout_scope { LayoutDiagnostic, LayoutError, LayoutSeverity }
    layout_types ++> n1_acceptance { LayoutSpec, fill_axis, fixed_axis, grow_axis }
    include layout_types ++> renderer {
        FrameEntry,
        LayoutResult,
        LayoutSpec,
        LayoutState,
        Rect,
        Viewport,
        clear_node,
        create_layout_state,
        frame_entry_of,
        rect_union,
        set_content,
        set_spec,
    }
    include layout_types ++> renderer_damage {
        LayoutResult,
        LayoutState,
        Rect,
        Viewport,
        rect_union,
    }
    layout_types ++> renderer_paint { FrameEntry, LayoutState }
    layout_types ++> renderer_types { LayoutState, Rect }
    layout_types ++> screen {
        AxisSize,
        SizeMode,
        LayoutSpec,
        LayoutDiagnostic,
        LayoutState,
        fixed_axis,
        set_spec,
    }
    include layout_types_core ++> layout_types {
        Rect,
        Size,
        rect_union,
        Axis,
        SizeMode,
        Align,
        OverlayAnchor,
        AxisSize,
        LayoutSpec,
        LayoutSeverity,
        LayoutError,
        Viewport,
        RelationHandle,
        LayoutDiagnostic,
        FrameEntry,
        LayoutFrame,
        MutationResult,
        LayoutResult,
        LayoutRelationKind,
        LayoutRelation,
        ContentEntry,
        MeasureEntry,
        LayoutState,
    }
    markdown_proj ++> transcript { looks_like_markdown, project_markdown, proj_lines_to_span_dicts }
    markup ++> gates { lower_markup, default_shell_registry, register_tag, create_tag_registry }
    model ++> demo_complex_shell { node_id }
    model ++> editor { Prompt }
    model ++> events {
        UiNode,
        UiContainer,
        Screen,
        Overlay,
        Child,
        Layer,
        node_id,
        ordered_children,
    }
    model ++> gates { MainScreen, ordered_child_keys }
    model ++> inspect {
        UiNode,
        UiContainer,
        Screen,
        Child,
        Owns,
        Feeds,
        FocusNext,
        Layer,
        node_id,
        ordered_children,
        ordered_child_keys,
        duplicate_sibling_keys,
        child_rank,
    }
    include model ++> layout { UiNode, UiContainer, Screen, Overlay, node_id, ordered_children }
    model ++> layout_compile { UiContainer, UiNode, node_id }
    include model ++> layout_compile_emit { UiNode }
    model ++> layout_compile_flow { UiContainer, node_id, ordered_children }
    model ++> layout_compile_model { UiNode }
    include model ++> layout_compile_overlays { UiNode }
    model ++> layout_compile_scope {
        Child,
        Layer,
        Overlay,
        Screen,
        UiContainer,
        UiNode,
        node_id,
        ordered_children,
    }
    model ++> layout_scope {
        UiNode,
        UiContainer,
        Screen,
        Overlay,
        Child,
        Layer,
        node_id,
        ordered_children,
    }
    model ++> layout_types { UiNode, node_id }
    include model ++> layout_types_core { UiNode, node_id }
    model ++> markup {
        UiNode,
        UiContainer,
        MainScreen,
        Header,
        TranscriptView,
        Status,
        Prompt,
        ApprovalOverlay,
    }
    include model ++> mutation {
        UiNode,
        UiContainer,
        UiSessionRoot,
        MainScreen,
        Header,
        TranscriptView,
        Status,
        Prompt,
        Child,
        Owns,
        Feeds,
        FocusNext,
        Layer,
        child_parent,
        child_rank,
        duplicate_sibling_keys,
        is_child_ancestor,
        node_id,
        ordered_child_keys,
        ordered_children,
    }
    model ++> progress_bar { UiNode }
    include model ++> renderer { UiNode, UiContainer, Screen, Overlay, ordered_children, node_id }
    model ++> renderer_damage { UiNode, UiContainer, Screen, ordered_children, node_id }
    model ++> renderer_paint {
        UiNode,
        UiContainer,
        Screen,
        Overlay,
        Layer,
        ordered_children,
        node_id,
    }
    model ++> renderer_types { UiNode }
    include model ++> runtime {
        UiNode,
        UiContainer,
        UiSessionRoot,
        Screen,
        Overlay,
        Child,
        Feeds,
        FocusNext,
        Layer,
        Owns,
        node_id,
        ordered_children,
    }
    include model ++> runtime_core {
        UiNode,
        UiContainer,
        UiSessionRoot,
        Screen,
        Overlay,
        Child,
        Feeds,
        FocusNext,
        Layer,
        Owns,
        node_id,
        ordered_children,
    }
    model ++> screen {
        MainScreen,
        Header,
        TranscriptView,
        Status,
        Prompt,
        ApprovalOverlay,
        UiNode,
        node_id,
    }
    model ++> transcript { TranscriptView }
    mutation ++> markup { append_child }
    include mutation ++> runtime { append_child, dispose_subtree, MutationResult }
    mutation ++> runtime_core { append_child, dispose_subtree, MutationResult }
    osp_walk ++> runtime_jids { ui_jids_reachable_from_nodes }
    progress_bar ++> demo_complex_shell { ProgressBar, SetProgress, render_progress }
    progress_bar ++> demo_live_shell { ProgressBar, SetProgress }
    progress_bar ++> demo_live_shell_model { ProgressBar }
    progress_bar ++> gates { ProgressBar, SetProgress, render_progress, register_progress_markup }
    include renderer ++> demo_complex_shell {
        create_renderer,
        render_frame,
        set_node_content,
        set_node_contract,
        mark_semantic_dirty,
        mark_layout_dirty,
        request_cursor,
        frame_used_full_clear,
    }
    renderer ++> demo_complex_shell_render {
        Renderer,
        set_node_content,
        set_node_contract,
        mark_semantic_dirty,
        mark_layout_dirty,
    }
    include renderer ++> demo_live_shell {
        Renderer,
        create_renderer,
        render_frame,
        set_node_content,
        set_node_contract,
        mark_semantic_dirty,
        mark_layout_dirty,
        request_cursor,
    }
    renderer ++> demo_live_shell_model { Renderer }
    renderer ++> demo_live_shell_render {
        render_frame,
        set_node_content,
        set_node_contract,
        mark_semantic_dirty,
        mark_layout_dirty,
        request_cursor,
    }
    renderer ++> gates { create_renderer, render_frame, set_node_content }
    renderer ++> n1_acceptance {
        create_renderer,
        render_frame,
        set_node_contract,
        set_node_content,
        mark_semantic_dirty,
        Renderer,
    }
    renderer_damage ++> renderer {
        compute_damage,
        _diff_ansi,
        _merge_damage,
        _resolve_cursor,
        _run_layout,
        _snapshot_rects,
    }
    renderer_paint ++> renderer { _paint_frame_buffer }
    renderer_paint ++> renderer_damage { _layered_overlays }
    renderer_types ++> renderer { DamageRect, FrameResult, Renderer }
    renderer_types ++> renderer_damage { AnsiDiff, CursorPos, DamageRect, Renderer }
    renderer_types ++> renderer_paint { Renderer, _OverlayHit }
    runtime ++> demo_complex_shell { create_session, dispose_session }
    include runtime ++> demo_live_shell { UiSession, create_session, dispose_session }
    runtime ++> demo_live_shell_model { UiSession }
    include runtime ++> editor { UiSession }
    runtime ++> events { UiSession }
    include runtime ++> focus {
        OverlayBounds,
        OverlayOpenResult,
        OverlayCloseResult,
        layers_paint_order,
        layers_input_order,
        focus_order,
        advance_focus,
        open_modal_overlay,
        close_overlay,
    }
    runtime ++> gates { create_session, dispose_session }
    runtime ++> inspect { UiSession, validate_session }
    runtime ++> n1_acceptance { create_session, dispose_session }
    runtime ++> screen {
        UiSession,
        make_session_event,
        OverlayOpenResult,
        OverlayCloseResult,
        OverlayBounds,
        append_child_session,
        set_current_screen,
        set_focus,
        open_modal_overlay,
        close_overlay,
        track_node,
        register_capability,
    }
    include runtime_core ++> runtime {
        RendererState,
        CapabilityRegistry,
        InvalidationRecord,
        SessionEventRecord,
        make_session_event,
        UiSession,
        SessionLeak,
        UiSessionHandle,
        create_session,
        track_node,
        is_reachable_from_root,
        assert_mutation_parent,
        append_child_session,
        set_current_screen,
        set_focus,
        register_capability,
        release_capabilities,
        record_invalidation,
        validate_session,
        dispose_session,
        get_focus_node,
    }
    runtime_jids ++> demo_complex_shell { ui_jids_reachable_from_persistent_root }
    runtime_jids ++> gates { ui_jids_reachable_from_persistent_root }
    screen ++> demo_complex_shell {
        build_main_shell,
        install_shell_contracts,
        shell_ids,
        shell_insert_text,
        shell_submit,
        shell_open_approval,
        shell_close_approval,
        shell_resize,
    }
    screen ++> demo_complex_shell_render { ShellScreen }
    include screen ++> demo_live_shell {
        ShellScreen,
        build_main_shell,
        install_shell_contracts,
        shell_insert_text,
        shell_submit,
        shell_cancel,
        shell_open_approval,
        shell_close_approval,
        shell_resize,
    }
    screen ++> gates {
        build_main_shell,
        configure_main_shell_layout,
        install_shell_contracts,
        shell_insert_text,
        shell_open_approval,
        shell_close_approval,
        shell_resize,
    }
    screen ++> n1_acceptance {
        build_main_shell,
        shell_insert_text,
        shell_cancel,
        shell_resize,
        shell_ids,
        ShellScreen,
    }
    terminal ++> demo_live_shell { ProcessTerminal, read_terminal_size }
    terminal ++> demo_live_shell_model { ProcessTerminal }
    terminal ++> emulated_terminal {
        Terminal,
        ENTER_ALT_SCREEN,
        LEAVE_ALT_SCREEN,
        ENABLE_BRACKETED_PASTE,
        DISABLE_BRACKETED_PASTE,
        SYNC_BEGIN,
        SYNC_END,
        HIDE_CURSOR,
        SHOW_CURSOR,
    }
    terminal ++> host { Terminal }
    terminal ++> n1_acceptance { ProcessTerminal }
    terminal ++> renderer { Terminal, synchronized_write }
    terminal ++> virtual_terminal {
        Terminal,
        ENTER_ALT_SCREEN,
        LEAVE_ALT_SCREEN,
        ENABLE_BRACKETED_PASTE,
        DISABLE_BRACKETED_PASTE,
        SYNC_BEGIN,
        SYNC_END,
        HIDE_CURSOR,
        SHOW_CURSOR,
        CLEAR_SCREEN,
    }
    transcript ++> demo_complex_shell {
        TranscriptMessage,
        bind_transcript,
        apply_transcript_revision,
        materialize_visible,
        set_follow_tail,
    }
    include transcript ++> demo_live_shell {
        TranscriptMessage,
        TranscriptProjection,
        bind_transcript,
        apply_transcript_revision,
        materialize_visible,
        set_follow_tail,
    }
    transcript ++> demo_live_shell_messages { TranscriptMessage, apply_transcript_revision }
    transcript ++> demo_live_shell_model { TranscriptMessage, TranscriptProjection }
    transcript ++> demo_live_shell_render { materialize_visible }
    virtual_terminal ++> demo_complex_shell { VirtualTerminal }
    virtual_terminal ++> gates { VirtualTerminal }
    virtual_terminal ++> n1_acceptance { VirtualTerminal }
    vt_screen ++> emulated_terminal { VtScreen, VtCell }
    width ++> cells { segment_graphemes, grapheme_width }
    include width ++> demo_live_shell { display_width, truncate_text }
    width ++> demo_live_shell_render { display_width, truncate_text }
    width ++> editor { display_width }
    width ++> layout { wrap_text_joined }
    width ++> layout_measure { display_width, wrap_text_joined }
    width ++> markdown_proj { wrap_text, display_width }
    width ++> transcript { wrap_text }
    width ++> vt_screen { grapheme_width }
}

graph import agent {
    openai_accounts ++> openai_login {
        ISSUER,
        RESOURCE,
        host_identity,
        selected_account,
        request_json,
        token_record,
        save_account,
    }
    openai_identity ++> openai_accounts { validate_identity }
}

graph import {
    agent.openai_accounts ++> agent.llm_transport { configured_account, account_revision }
    agent.openai_responses ++> agent.llm_transport { responses_stream }
}

graph import {
    agent.openai_login ++> tui.picker_actions { start_login, cancel_login, poll_login }
    agent.openai_accounts ++> tui.picker_actions { configured_account }
    agent.model_catalog ++> tui.picker_actions { invalidate_openai_catalog, warm_model_catalog }
    tui.picker_actions ++> tui.input { _tick_login }
}

graph import {
    agent.openai_accounts ++> agent.auth_env { logout_account, configured_account }
}

graph import {
    agent.openai_accounts ++> agent.model_catalog { configured_account, request_json, access_token }
}

graph import agent {
    openai_accounts ++> openai_responses { access_token }
}

graph import {
    agent.openai_accounts ++> tui.picker_actions { read_accounts, select_account }
}

graph import {
    agent.openai_accounts ++> agent.model_catalog { account_revision }
    agent.model_catalog ++> tui.overlay { account_model_label }
}

graph import {
    agent.openai_accounts ++> agent.openai_login { logout_account }
    agent.openai_login ++> tui.commands { start_logout }
}
