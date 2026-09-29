# 敌人清理：旧测试替代清单

每项均按旧断言及当前需求核对。旧固定概率触发、旧节点路径、旧全锥禁射不再是运行约定；有效的几何、实射、搜索覆盖、换弹和保持断言迁到当前接口。原脚本仍可从 Git 历史检索；此次原文审计副本在忽略的 logs/enemy_cleanup_baseline/retired_tests。

| 已移除旧入口 | 当前覆盖及规则变化 |
|---|---|
| `arena_activation_test` | enemy_scene_test（入场、离场、复位、区域外受击） |
| `attack_action_interface_test` | enemy_modular_contract_test、enemy_optional_removal_test（统一动作协议替代旧启动信号） |
| `attack_position_action_test` | attack_point_validation_test、attack_hold_regression_test、utility_runtime_test、enemy_configuration_lifecycle_test（旧概率触发不再是需求） |
| `attack_position_hit_test` | search_evidence_test、utility_score_test、enemy_scene_test（受击提供证据，不直接强启旧攻击流程） |
| `attack_shot_clearance_test` | enemy_firing_lane_test、attack_region_quality_test（远处极端散布不再一票否决，旧无遮挡架枪预期已过时） |
| `utility_firing_lane_test` | enemy_firing_lane_test、utility_collision_recovery_test、close_range_spacing_test（枪口受阻、评分/移动恢复） |
| `cover_b_corner_test` | attack_point_validation_test、attack_points_test、cover_tactical_safety_test（通行、转角和实际遮挡） |
| `cover_damage_reaction_test` | search_evidence_test、retreat_fire_credit_test、attack_points_test（受击证据和四面比例；旧强制冲刺规则已取消） |
| `cover_region_test` | attack_points_test、cover_tactical_safety_test、stationary_cover_search_test（几何、路径和隐藏到搜寻实走） |
| `cover_four_faces_test` | attack_points_test、cover_tactical_safety_test、exit_suppression_geometry_test（四面/短面、导航与碰撞） |
| `cover_search_regression_test` | search_area_coverage_test（完整保留三个种子的实走及独立密采样）、utility_collision_recovery_test（转移恢复） |
| `enemy_ai_regression_test` | run_enemy_regressions.py（过时聚合入口） |
| `enemy_cover_test` | cover_tactical_safety_test、stationary_cover_search_test、enemy_scene_test（旧节点结构及固定概率已取消） |
| `enemy_reaction_test` | search_evidence_test、aim_disruption_test、hearing_test（真实伤害、证据与感知） |
| `patrol_test` | enemy_scene_test、utility_score_test（无玩家自由巡逻旧要求已取消） |
| `ranged_position_test` | close_range_spacing_test、utility_runtime_test、enemy_scene_test（保持距离和近战切换） |
| `enemy_reload_cover_test` | reload_approach_timing_test、enemy_reload_test（换弹速度、计时、脚步与路线） |
| `enemy_reload_decision_test` | utility_score_test、reload_approach_timing_test、enemy_reload_test、utility_collision_recovery_test（三方案与途中切换） |
| `enemy_shooting_test` | enemy_fire_timing_test、enemy_fire_decision_test、enemy_basic_capabilities_test、enemy_probability_test（实射与资格） |
| `enemy_stability_fire_test` | enemy_fire_decision_test、enemy_weapon_test（稳定度与等待射击） |
| `exit_suppression_test` | exit_suppression_geometry_test、utility_suppression_trigger_test、utility_suppression_blocked_test（旧攻击扇环不能作出口） |
| `suppression_test` | suppression_lane_test、utility_suppression_trigger_test、enemy_optional_removal_test（统一参选与权限撤销） |
| `suppression_dispatch_test` | utility_suppression_trigger_test、utility_suppression_blocked_test（旧动作直调分派已取消） |
| `utility_ai_test` | utility_score_test、enemy_modular_contract_test、utility_runtime_test（共同评分、协议与完整执行） |
| `utility_cover_modes_test` | retreat_fire_credit_test、utility_search_cover_test、utility_collision_recovery_test（同评分、实际火力及搜索转移） |
| `covering_retreat_fire_test` | retreat_fire_credit_test、enemy_fire_timing_test（撤退计分与真实射击节奏） |
| `search_walk_regression_test` | search_area_coverage_test（旧包装入口合并） |

另保留并迁移 `enemy_basic_capabilities_test`、`enemy_reload_test`、`attack_hold_regression_test`；武器和概率测试不是废弃代码，保留并加入正式运行器。`test_enemy_probability_inspector` 依赖打开的编辑器场景，继续保留为人工编辑器专项。
