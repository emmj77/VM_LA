# Blender — 2500 fiches : 102 fusions a geste, et les preuves

Etat au 20/10 apres le passage au porteur declaratif (`machine: blender` + `op:`, un seul
`config/engine/tools.sh`). Chiffres releves dans `config/tools/blender/` et `config/la_tools.yaml`.

## Resultat

| | |
|---|---|
| fiches avant | 2500 |
| fiches apres | 1796 |

| fusions | **102** |
| operateurs couverts | **806** sur 2498 (32 %) |
| economie | **704 fiches** (-28 %) |
| jonctions entre familles differentes | **0** |

Le reste (1692 fiches) garde son nom et son corps : c'est la ou l'argument porterait un
AUTRE geste, ou les parametres divergent trop (import/export, `select_*`, `view_*`).

## Le critere (celui de Moussa)

Bon : les outils agissent sur LA MEME CHOSE avec le meme genre d'action, et la variante est une
valeur fermee. `blender_marker_item{geste: add|delete|duplicate|move|rename}` : un marqueur,
cinq gestes. Mauvais : la jonction approximative entre deux choses differentes (`clip` avec
`curve` parce que les deux ont un `select_all`).

## La forme d'une fiche fusionnee (porteur declaratif)

    tool: "blender_marker_item"
    doc: blender
    RULES:      {enabled: true, timeout: 120}
    DESCRIPTION: "a timeline marker: add | delete | duplicate | move | rename (geste picks which)"
    COMMAND: |
      exec dash "$ROOT/config/engine/tools.sh" blender --op "marker.{{geste}}" --arg "frames={{frames}}" ...
    ARGS:
      - {name: geste, type: enum, values: [add, delete, duplicate, move, rename]}
      - {name: frames, type: int}

Trois choses font la solidite, et elles sont deja dans le moteur :

1. **`type: enum` + `values`** : le moteur refuse une valeur hors liste AVANT de lancer
   Blender, en la nommant : `bidon is not in the closed list of geste ; values : add | delete
   | duplicate | move | rename`, et il refuse aussi la valeur vide. C'est la garde qui remplace
   les noms disparus, et elle ferme la porte a une valeur qui serait une commande.
2. **L'argument s'appelle `geste` partout, jamais `action`/`type`/`mode`** : `action` est DEJA
   un argument de 8 operateurs (`object.vertex_group_*`, `anim.channels_*`, `object.shape_key_*`,
   `clip.*_tracks`, `mball.*`), `type` chez `sequencer.*_strip_add`, `mode` chez
   `marker.select`/`mesh.primitive`/`transform.*`. Un `action` discriminant serait parti a Blender
   colle a l'argument `action`. `geste` n'existe dans aucun des 1559 noms d'arguments.
   Quand une fiche n'a pas d'axe de verbe (primitives : toutes en `_add`), l'argument porte le nom
   de la propriete (`geste: circle|cone|...` sur `mesh.primitive_{{geste}}_add`).
3. **L'operation est un gabarit** : `--op "marker.{{geste}}"`. Une seule valeur fermee, pas de
   `case`, donc rien qui puisse deriver entre la liste et le corps.

## Ce qui a ete execute, pas seulement ecrit

    refus hors liste      blender_marker_item {geste:bidon}       -> refuse + les 5 valeurs
    refus valeur vide     blender_marker_item (sans geste)        -> refuse + les 5 valeurs
    equivalence           blender_marker_item {geste:add}  ==  ancien blender_marker_add
                          (meme refus Blender : marker.add poll() failed, context is incorrect)
    succes reel           blender_mesh_primitive {geste:cube}    -> mesh.primitive_cube_add FINISHED
    succes reel           blender_mesh_primitive {geste:monkey}  -> mesh.primitive_monkey_add FINISHED
    deux axes             blender_node_socket_item {geste:add, kind:bake_node}
                          -> node.bake_node_item_add (les deux valeurs substituees)
    gros args             blender_object_vertex_group {geste:smooth} (25 args, vides)
                          -> object.vertex_group_smooth
    operation qui tourne  blender_fluid_bake {geste:free, part:particles} -> fluid.free_particles
                          -> 'No Fluid modifier found' (l'operation a bien tourne)

Controle statique des 102 fiches : chaque `{{trou}}` de la commande est declare dans ARGS,
chaque argument declare est utilise, aucun doublon, aucune commande hors de la forme du porteur.

## Trois exceptions assumees

1. `mesh.primitive_cube_add_gizmo` reste sa propre fiche : c'est la seule primitive a porter
   `_gizmo`, l'inclure aurait fait un enum a trous.
2. `render.preset_add`, `clip.add_marker`, `marker.select` (l'operation nue, sans suffixe) restent
   leurs propres fiches : leur variante serait la valeur VIDE, qu'un enum ne sait pas porter.
3. `node.interface_item_remove` reste seul (il n'a pas de `add` ni de `move`).

## Etat du catalogue

    2500 -> 1796 fiches      |  1796 fichiers = 1796 entrees de registre (bijection verifiee)
    blender_tools_find      : ls marker rend les fiches fusionnees avec leur description
    807 corps partis a la corbeille (gio trash), aucun rm

## Les 77 sous-familles

### object — 250 ops — 6 fusion(s), 67 fiche(s) gagnee(s)
- `blender_object_vertex_group` : 22 -> 1 — vertex_group_add, vertex_group_assign, vertex_group_assign_new, vertex_group_clean, vertex_group_copy, vertex_group_copy_to_selected, vertex_group_deselect, vertex_group_invert…
- `blender_object_modifier` : 12 -> 1 — modifier_add, modifier_add_node_group, modifier_apply, modifier_apply_as_shapekey, modifier_convert, modifier_copy, modifier_copy_to_selected, modifier_move_down…
- `blender_object_clear` : 12 -> 1 — constraints_clear, hide_view_clear, lineart_clear, location_clear, modifiers_clear, origin_clear, parent_clear, paths_clear…
- `blender_object_shape_key` : 11 -> 1 — shape_key_add, shape_key_apply_to_basis, shape_key_clear, shape_key_copy, shape_key_lock, shape_key_make_basis, shape_key_mirror, shape_key_move…
- `blender_object_material_slot` : 9 -> 1 — material_slot_add, material_slot_assign, material_slot_copy, material_slot_deselect, material_slot_move, material_slot_remove, material_slot_remove_all, material_slot_remove_unused…
- `blender_object_hook` : 7 -> 1 — hook_add_newob, hook_add_selob, hook_assign, hook_recenter, hook_remove, hook_reset, hook_select

### node — 182 ops — 3 fusion(s), 74 fiche(s) gagnee(s)
- `blender_node_toggle` : 9 -> 1 — collapse_hide_unused_toggle, hide_socket_toggle, hide_toggle, interface_item_make_panel_toggle, interface_item_new_panel_toggle, interface_item_unlink_panel_toggle, mute_toggle, options_toggle…
- `blender_node_socket_item` : 66 -> 1 — bake_node_item_add, bake_node_item_move, bake_node_item_remove, capture_attribute_item_add, capture_attribute_item_move, capture_attribute_item_remove, closure_input_item_add, closure_input_item_move…
- `blender_node_cryptomatte_layer` : 2 -> 1 — cryptomatte_layer_add, cryptomatte_layer_remove

### mesh — 167 ops — 3 fusion(s), 29 fiche(s) gagnee(s)
- `blender_mesh_extrude` : 13 -> 1 — extrude_context, extrude_context_move, extrude_edges_indiv, extrude_edges_move, extrude_faces_indiv, extrude_faces_move, extrude_manifold, extrude_region…
- `blender_mesh_primitive` : 10 -> 1 — primitive_circle_add, primitive_cone_add, primitive_cube_add, primitive_cylinder_add, primitive_grid_add, primitive_ico_sphere_add, primitive_monkey_add, primitive_plane_add…
- `blender_mesh_polybuild` : 9 -> 1 — polybuild_delete_at_cursor, polybuild_dissolve_at_cursor, polybuild_extrude_at_cursor_move, polybuild_face_at_cursor, polybuild_face_at_cursor_move, polybuild_split_at_cursor, polybuild_split_at_cursor_move, polybuild_transform_at_cursor…

### grease_pencil — 123 ops — 3 fusion(s), 33 fiche(s) gagnee(s)
- `blender_gp_layer` : 17 -> 1 — layer_active, layer_add, layer_duplicate, layer_duplicate_object, layer_group_add, layer_group_color_tag, layer_group_remove, layer_hide…
- `blender_gp_stroke` : 10 -> 1 — stroke_material_set, stroke_merge_by_distance, stroke_reset_vertex_color, stroke_simplify, stroke_smooth, stroke_split, stroke_subdivide, stroke_subdivide_smooth…
- `blender_gp_material` : 9 -> 1 — material_copy_to_object, material_hide, material_isolate, material_lock_all, material_lock_unselected, material_lock_unused, material_reveal, material_select…

### wm — 117 ops — 1 fusion(s), 14 fiche(s) gagnee(s)
- `blender_wm_context` : 15 -> 1 — context_cycle_array, context_cycle_enum, context_cycle_int, context_menu_enum, context_pie_enum, context_scale_float, context_scale_int, context_set_boolean…

### sequencer — 111 ops — 3 fusion(s), 25 fiche(s) gagnee(s)
- `blender_sequencer_text` : 12 -> 1 — text_cursor_move, text_cursor_set, text_delete, text_deselect_all, text_edit_copy, text_edit_cut, text_edit_mode_toggle, text_edit_paste…
- `blender_sequencer_retiming` : 9 -> 1 — retiming_add_freeze_frame_slide, retiming_add_transition_slide, retiming_freeze_frame_add, retiming_key_add, retiming_key_delete, retiming_reset, retiming_segment_speed_set, retiming_show…
- `blender_sequencer_strip_add` : 7 -> 1 — effect_strip_add, image_strip_add, mask_strip_add, movie_strip_add, movieclip_strip_add, scene_strip_add, sound_strip_add

### clip — 92 ops — 3 fusion(s), 14 fiche(s) gagnee(s)
- `blender_clip_tracks` : 8 -> 1 — average_tracks, clean_tracks, copy_tracks, filter_tracks, hide_tracks, join_tracks, lock_tracks, paste_tracks
- `blender_clip_stabilize` : 6 -> 1 — stabilize_2d_add, stabilize_2d_remove, stabilize_2d_rotation_add, stabilize_2d_rotation_remove, stabilize_2d_rotation_select, stabilize_2d_select
- `blender_clip_marker_add` : 3 -> 1 — add_marker_at_click, add_marker_move, add_marker_slide

### outliner — 73 ops — 4 fusion(s), 41 fiche(s) gagnee(s)
- `blender_outliner_collection` : 24 -> 1 — collection_color_tag_set, collection_disable, collection_disable_render, collection_duplicate, collection_duplicate_linked, collection_enable, collection_enable_render, collection_exclude_clear…
- `blender_outliner_item_operation` : 9 -> 1 — animdata_operation, constraint_operation, data_operation, lib_operation, liboverride_operation, liboverride_troubleshoot_operation, modifier_operation, object_operation…
- `blender_outliner_id` : 6 -> 1 — id_copy, id_delete, id_linked_relocate, id_operation, id_paste, id_remap
- `blender_outliner_drop` : 6 -> 1 — collection_drop, datastack_drop, item_drag_drop, material_drop, parent_drop, scene_drop

### view3d — 68 ops — 3 fusion(s), 12 fiche(s) gagnee(s)
- `blender_view3d_snap` : 7 -> 1 — snap_cursor_to_active, snap_cursor_to_center, snap_cursor_to_grid, snap_cursor_to_selected, snap_selected_to_active, snap_selected_to_cursor, snap_selected_to_grid
- `blender_view3d_ndof` : 4 -> 1 — ndof_all, ndof_orbit, ndof_orbit_zoom, ndof_pan
- `blender_view3d_edit_extrude` : 4 -> 1 — edit_mesh_extrude_individual_move, edit_mesh_extrude_manifold_normal, edit_mesh_extrude_move_normal, edit_mesh_extrude_move_shrink_fatten

### graph — 67 ops — 2 fusion(s), 6 fiche(s) gagnee(s)
- `blender_graph_fmodifier` : 4 -> 1 — fmodifier_add, fmodifier_copy, fmodifier_delete, fmodifier_paste
- `blender_graph_blend` : 4 -> 1 — blend_offset, blend_to_default, blend_to_ease, blend_to_neighbor

### anim — 65 ops — 4 fusion(s), 35 fiche(s) gagnee(s)
- `blender_anim_channels` : 19 -> 1 — channels_bake, channels_clean_empty, channels_click, channels_collapse, channels_delete, channels_editable_toggle, channels_expand, channels_fcurves_enable…
- `blender_anim_keyframe` : 9 -> 1 — keyframe_clear_button, keyframe_clear_v3d, keyframe_clear_vse, keyframe_delete_button, keyframe_delete_by_name, keyframe_delete_v3d, keyframe_delete_vse, keyframe_insert_button…
- `blender_anim_keying_set` : 6 -> 1 — keying_set_active_set, keying_set_add, keying_set_export, keying_set_path_add, keying_set_path_remove, keying_set_remove
- `blender_anim_slot` : 5 -> 1 — slot_channels_move_to_new_action, slot_new_for_id, slot_unassign_from_constraint, slot_unassign_from_id, slot_unassign_from_nla_strip

### paint — 55 ops — 2 fusion(s), 20 fiche(s) gagnee(s)
- `blender_paint_select` : 15 -> 1 — face_select_all, face_select_hide, face_select_less, face_select_linked, face_select_linked_pick, face_select_loop, face_select_more, vert_select_all…
- `blender_paint_gesture` : 7 -> 1 — hide_show_lasso_gesture, hide_show_line_gesture, hide_show_polyline_gesture, mask_box_gesture, mask_lasso_gesture, mask_line_gesture, mask_polyline_gesture

### uv — 55 ops — 1 fusion(s), 3 fiche(s) gagnee(s)
- `blender_uv_project` : 4 -> 1 — cube_project, cylinder_project, smart_project, sphere_project

### curve — 51 ops — 2 fusion(s), 6 fiche(s) gagnee(s)
- `blender_curve_primitive` : 5 -> 1 — primitive_bezier_circle_add, primitive_bezier_curve_add, primitive_nurbs_circle_add, primitive_nurbs_curve_add, primitive_nurbs_path_add
- `blender_curve_smooth_set` : 3 -> 1 — smooth_radius, smooth_tilt, smooth_weight

### pose — 51 ops — 3 fusion(s), 20 fiche(s) gagnee(s)
- `blender_pose_selection_set` : 12 -> 1 — selection_set_add, selection_set_add_and_assign, selection_set_assign, selection_set_copy, selection_set_delete_all, selection_set_deselect, selection_set_move, selection_set_paste…
- `blender_pose_clear` : 7 -> 1 — constraints_clear, ik_clear, loc_clear, rot_clear, scale_clear, transforms_clear, user_transforms_clear
- `blender_pose_paths` : 4 -> 1 — paths_calculate, paths_clear, paths_range_update, paths_update

### armature — 49 ops — 1 fusion(s), 11 fiche(s) gagnee(s)
- `blender_armature_collection` : 12 -> 1 — collection_add, collection_assign, collection_create_and_assign, collection_deselect, collection_move, collection_remove, collection_remove_unused, collection_select…

### image — 49 ops — 1 fusion(s), 3 fiche(s) gagnee(s)
- `blender_image_render_slot` : 4 -> 1 — add_render_slot, clear_render_slot, cycle_render_slot, remove_render_slot

### screen — 43 ops — 3 fusion(s), 14 fiche(s) gagnee(s)
- `blender_screen_area` : 7 -> 1 — area_close, area_dupli, area_join, area_move, area_options, area_split, area_swap
- `blender_screen_region` : 6 -> 1 — region_blend, region_context_menu, region_flip, region_quadview, region_scale, region_toggle
- `blender_screen_jump` : 4 -> 1 — frame_jump, keyframe_jump, marker_jump, time_jump

### text — 43 ops — 2 fusion(s), 17 fiche(s) gagnee(s)
- `blender_text_edit` : 14 -> 1 — autocomplete, copy, delete, indent, indent_or_autocomplete, insert, line_break, move…
- `blender_text_search` : 5 -> 1 — find, find_set_selected, replace, replace_set_selected, start_find

### file — 40 ops — 1 fusion(s), 3 fiche(s) gagnee(s)
- `blender_file_bookmark` : 4 -> 1 — bookmark_add, bookmark_cleanup, bookmark_delete, bookmark_move

### mask — 40 ops — 2 fusion(s), 6 fiche(s) gagnee(s)
- `blender_mask_vertex_add` : 4 -> 1 — add_feather_vertex, add_feather_vertex_slide, add_vertex, add_vertex_slide
- `blender_mask_shape_key` : 4 -> 1 — shape_key_clear, shape_key_feather_reset, shape_key_insert, shape_key_rekey

### nla — 39 ops — 1 fusion(s), 4 fiche(s) gagnee(s)
- `blender_nla_add` : 5 -> 1 — actionclip_add, meta_add, soundclip_add, tracks_add, transition_add

### scene — 39 ops — 2 fusion(s), 10 fiche(s) gagnee(s)
- `blender_scene_view_layer` : 8 -> 1 — view_layer_add, view_layer_add_aov, view_layer_add_lightgroup, view_layer_add_used_lightgroups, view_layer_remove, view_layer_remove_aov, view_layer_remove_lightgroup, view_layer_remove_unused_lightgroups
- `blender_scene_freestyle_modifier` : 4 -> 1 — freestyle_alpha_modifier_add, freestyle_color_modifier_add, freestyle_geometry_modifier_add, freestyle_thickness_modifier_add

### sculpt — 39 ops — 2 fusion(s), 12 fiche(s) gagnee(s)
- `blender_sculpt_gesture` : 9 -> 1 — face_set_box_gesture, face_set_lasso_gesture, face_set_line_gesture, face_set_polyline_gesture, project_line_gesture, trim_box_gesture, trim_lasso_gesture, trim_line_gesture…
- `blender_sculpt_mask` : 5 -> 1 — mask_by_color, mask_filter, mask_from_boundary, mask_from_cavity, mask_init

### ui — 38 ops — 2 fusion(s), 17 fiche(s) gagnee(s)
- `blender_ui_button` : 11 -> 1 — assign_default_button, copy_as_driver_button, copy_data_path_button, copy_driver_to_selected_button, copy_python_command_button, copy_to_selected_button, jump_to_target_button, override_add_button…
- `blender_ui_eyedropper` : 8 -> 1 — eyedropper_bone, eyedropper_color, eyedropper_colorramp, eyedropper_colorramp_point, eyedropper_depth, eyedropper_driver, eyedropper_grease_pencil_color, eyedropper_id

### action — 37 ops — 1 fusion(s), 4 fiche(s) gagnee(s)
- `blender_action_type` : 5 -> 1 — easing_type, extrapolation_type, handle_type, interpolation_type, keyframe_type

### particle — 37 ops — 2 fusion(s), 6 fiche(s) gagnee(s)
- `blender_particle_dupliob` : 5 -> 1 — dupliob_copy, dupliob_move_down, dupliob_move_up, dupliob_refresh, dupliob_remove
- `blender_particle_target` : 3 -> 1 — target_move_down, target_move_up, target_remove

### preferences — 37 ops — 4 fusion(s), 22 fiche(s) gagnee(s)
- `blender_preferences_item` : 10 -> 1 — asset_library_add, asset_library_remove, autoexec_path_add, autoexec_path_remove, extension_repo_add, extension_repo_remove, keyitem_add, keyitem_remove…
- `blender_preferences_addon` : 7 -> 1 — addon_disable, addon_enable, addon_expand, addon_install, addon_refresh, addon_remove, addon_show
- `blender_preferences_keyconfig` : 5 -> 1 — keyconfig_activate, keyconfig_export, keyconfig_import, keyconfig_remove, keyconfig_test
- `blender_preferences_studiolight` : 4 -> 1 — studiolight_copy_settings, studiolight_install, studiolight_new, studiolight_uninstall

### extensions — 32 ops — 4 fusion(s), 26 fiche(s) gagnee(s)
- `blender_extensions_package` : 14 -> 1 — package_disable, package_install, package_install_files, package_install_marked, package_obsolete_marked, package_show_clear, package_show_set, package_show_settings…
- `blender_extensions_repo` : 7 -> 1 — repo_enable_from_drop, repo_lock_all, repo_refresh_all, repo_sync, repo_sync_all, repo_unlock, repo_unlock_all
- `blender_extensions_userpref` : 5 -> 1 — userpref_allow_online, userpref_allow_online_popup, userpref_show_for_update, userpref_show_online, userpref_tags_set
- `blender_extensions_package_mark` : 4 -> 1 — package_mark_clear, package_mark_clear_all, package_mark_set, package_mark_set_all

### curves — 31 ops — 1 fusion(s), 3 fiche(s) gagnee(s)
- `blender_curves_create` : 4 -> 1 — add_bezier, add_circle, draw, pen

### transform — 27 ops — 1 fusion(s), 12 fiche(s) gagnee(s)
- `blender_transform_modal` : 13 -> 1 — bend, mirror, push_pull, resize, rotate, shear, shrink_fatten, tosphere…

### font — 23 ops — 2 fusion(s), 11 fiche(s) gagnee(s)
- `blender_font_edit` : 7 -> 1 — delete, line_break, move, move_select, select_all, select_word, selection_set
- `blender_font_text` : 6 -> 1 — text_copy, text_cut, text_insert, text_insert_unicode, text_paste, text_paste_from_file

### asset — 21 ops — 1 fusion(s), 4 fiche(s) gagnee(s)
- `blender_asset_catalog` : 5 -> 1 — catalog_delete, catalog_new, catalog_redo, catalog_undo, catalog_undo_push

### console — 21 ops — 1 fusion(s), 10 fiche(s) gagnee(s)
- `blender_console_edit` : 11 -> 1 — autocomplete, copy, delete, indent, indent_or_autocomplete, insert, move, paste…

### constraint — 18 ops — 1 fusion(s), 3 fiche(s) gagnee(s)
- `blender_constraint_inverse` : 4 -> 1 — childof_clear_inverse, childof_set_inverse, objectsolver_clear_inverse, objectsolver_set_inverse

### render — 16 ops — 1 fusion(s), 5 fiche(s) gagnee(s)
- `blender_render_preset` : 6 -> 1 — color_management_white_balance_preset_add, cycles_integrator_preset_add, cycles_performance_preset_add, cycles_sampling_preset_add, cycles_viewport_sampling_preset_add, eevee_raytracing_preset_add

### fluid — 14 ops — 1 fusion(s), 11 fiche(s) gagnee(s)
- `blender_fluid_bake` : 12 -> 1 — bake_all, bake_data, bake_guides, bake_mesh, bake_noise, bake_particles, free_all, free_data…

### view2d — 14 ops — 1 fusion(s), 13 fiche(s) gagnee(s)
- `blender_view2d_navigate` : 14 -> 1 — edge_pan, ndof, pan, reset, scroll_down, scroll_left, scroll_right, scroll_up…

### ed — 13 ops — 1 fusion(s), 6 fiche(s) gagnee(s)
- `blender_ed_lib_id` : 7 -> 1 — lib_id_fake_user_toggle, lib_id_generate_preview, lib_id_generate_preview_from_object, lib_id_load_custom_preview, lib_id_override_editable_toggle, lib_id_remove_preview, lib_id_unlink

### rigidbody — 13 ops — 1 fusion(s), 3 fiche(s) gagnee(s)
- `blender_rigidbody_objects` : 4 -> 1 — object_add, object_remove, objects_add, objects_remove

### collection — 12 ops — 2 fusion(s), 8 fiche(s) gagnee(s)
- `blender_collection_exporter` : 6 -> 1 — exporter_add, exporter_export, exporter_move, exporter_remove, importer_add, importer_remove
- `blender_collection_objects` : 4 -> 1 — objects_add_active, objects_remove, objects_remove_active, objects_remove_all

### brush — 11 ops — 1 fusion(s), 6 fiche(s) gagnee(s)
- `blender_brush_asset` : 7 -> 1 — asset_activate, asset_delete, asset_edit_metadata, asset_load_preview, asset_revert, asset_save, asset_save_as

### marker — 11 ops — 2 fusion(s), 6 fiche(s) gagnee(s)
- `blender_marker_item` : 5 -> 1 — add, delete, duplicate, move, rename
- `blender_marker_select_mode` : 3 -> 1 — select_all, select_box, select_leftright

### geometry — 9 ops — 1 fusion(s), 7 fiche(s) gagnee(s)
- `blender_geometry_color_attribute` : 8 -> 1 — attribute_add, attribute_convert, attribute_remove, color_attribute_add, color_attribute_convert, color_attribute_duplicate, color_attribute_remove, color_attribute_render_set

### poselib — 9 ops — 1 fusion(s), 3 fiche(s) gagnee(s)
- `blender_poselib_asset` : 4 -> 1 — apply_pose_asset, blend_pose_asset, create_pose_asset, paste_asset

### boid — 8 ops — 2 fusion(s), 6 fiche(s) gagnee(s)
- `blender_boid_rule` : 4 -> 1 — rule_add, rule_del, rule_move_down, rule_move_up
- `blender_boid_state` : 4 -> 1 — state_add, state_del, state_move_down, state_move_up

### lattice — 8 ops — rien a fusionner

### mball — 8 ops — 1 fusion(s), 5 fiche(s) gagnee(s)
- `blender_mball_metaelems` : 6 -> 1 — delete_metaelems, duplicate_metaelems, duplicate_move, hide_metaelems, reveal_metaelems, select_random_metaelems

### paintcurve — 8 ops — rien a fusionner

### workspace — 8 ops — 1 fusion(s), 7 fiche(s) gagnee(s)
- `blender_workspace` : 8 -> 1 — add, append_activate, delete, delete_all_others, duplicate, reorder_to_back, reorder_to_front, scene_pin_toggle

### gpencil — 7 ops — 1 fusion(s), 2 fiche(s) gagnee(s)
- `blender_gpencil_layer_annotation` : 3 -> 1 — layer_annotation_add, layer_annotation_move, layer_annotation_remove

### info — 7 ops — 1 fusion(s), 2 fiche(s) gagnee(s)
- `blender_info_report` : 3 -> 1 — report_copy, report_delete, report_replay

### palette — 7 ops — 1 fusion(s), 2 fiche(s) gagnee(s)
- `blender_palette_color` : 3 -> 1 — color_add, color_delete, color_move

### pointcloud — 7 ops — rien a fusionner

### ptcache — 7 ops — 1 fusion(s), 6 fiche(s) gagnee(s)
- `blender_ptcache` : 7 -> 1 — add, bake, bake_all, bake_from_cache, free_bake, free_bake_all, remove

### sound — 7 ops — 1 fusion(s), 4 fiche(s) gagnee(s)
- `blender_sound_clip` : 5 -> 1 — mixdown, open, open_mono, pack, unpack

### spreadsheet — 7 ops — 2 fusion(s), 3 fiche(s) gagnee(s)
- `blender_spreadsheet_column` : 3 -> 1 — fit_column, reorder_columns, resize_column
- `blender_spreadsheet_filter` : 2 -> 1 — add_row_filter_rule, remove_row_filter_rule

### buttons — 6 ops — rien a fusionner

### surface — 6 ops — rien a fusionner

### cachefile — 5 ops — 1 fusion(s), 2 fiche(s) gagnee(s)
- `blender_cachefile_layer` : 3 -> 1 — layer_add, layer_move, layer_remove

### dpaint — 5 ops — rien a fusionner

### sculpt_curves — 4 ops — rien a fusionner

### texture — 4 ops — rien a fusionner

### cycles — 3 ops — rien a fusionner

### material — 3 ops — rien a fusionner

### script — 3 ops — rien a fusionner

### uilist — 3 ops — rien a fusionner

### camera — 2 ops — rien a fusionner

### export_scene — 2 ops — rien a fusionner

### gizmogroup — 2 ops — rien a fusionner

### import_scene — 2 ops — rien a fusionner

### world — 2 ops — rien a fusionner

### cloth — 1 ops — rien a fusionner

### export_anim — 1 ops — rien a fusionner

### import_anim — 1 ops — rien a fusionner

### import_curve — 1 ops — rien a fusionner

### text_editor — 1 ops — rien a fusionner

