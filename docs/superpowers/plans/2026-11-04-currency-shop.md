# Currency Shop and Task Rewards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the tavern three-choice reward with a `.tres`-driven currency shop, fixed one-time task payouts, level-gated visible goods, and checkpoint-consistent death refunds.

**Architecture:** Add generic shop resources plus a controller/board pair. Keep currency, rewarded task IDs, one-time purchases, and the level-entry snapshot in `GameState`; include them in campaign checkpoints so hotel return restores purchase and equipment state atomically. Reuse `RewardNPC` as the shop entrance while leaving old reward components available as isolated compatibility code.

**Tech Stack:** Godot 4.7.2, GDScript, `.tres` resources, SceneTree integration tests.

**Spec:** `docs/superpowers/specs/2026-11-04-currency-shop-design.md`

## Global Constraints

- Preserve existing `RewardNPC`, player, weapon, level, and script UID references wherever the old path is still used.
- Initial catalog contains exactly `first_aid`, `ammo`, and `system_progress`.
- Default prices are `40`, `30`, and `50`; task `money_reward` is `100` for each of the five main tasks.
- Locked items are completely hidden, never shown as disabled rows.
- `WEAPON` products reference existing `WeaponData`; purchasing chooses slot 0 (primary) or 1 (secondary) and overwrites that slot.
- Consumables repeat; one-time weapon products disappear after purchase.
- Death hotel return refunds post-checkpoint spending and restores purchase IDs plus the full equipment snapshot.
- Current-level retry restores the snapshot captured when entering that level, so paid equipment is not lost.
- No save-file persistence is added.
- Use real scene/state behavior in integration tests; do not weaken existing tests.
- Use `/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot` for direct local test commands.
- Commit generated `.gd.uid` sidecars for every new GDScript; do not commit `.godot` cache or logs.

---

## File Structure

**Create**
- `movement_demo/scripts/shop/shop_item_definition.gd` — inspectable product schema and effect enum.
- `movement_demo/scripts/shop/shop_catalog.gd` — ordered catalog and validated lookup.
- `movement_demo/scripts/shop/shop_controller.gd` — visibility, purchase transactions, pause ownership, player/equipment effects.
- `movement_demo/scripts/ui/shop_board.gd` — dynamic shop UI and purchase intent signals.
- `movement_demo/scenes/ui/shop_board.tscn` — reusable ALWAYS-process shop panel.
- `movement_demo/resources/shop/shop_catalog.tres` — three initial products.
- `movement_demo/tests/shop_catalog_test.gd` — schema/catalog tests.
- `movement_demo/tests/shop_state_test.gd` — currency, task reward, purchase, and checkpoint tests.
- `movement_demo/tests/shop_weapon_test.gd` — weapon replacement and retry-snapshot tests.
- `movement_demo/tests/shop_board_test.gd` — hidden rows, balance, and purchase intent tests.
- `movement_demo/tests/shop_flow_test.gd` — real NPC, shop, task payout, retry, and hotel-refund integration.

**Modify**
- `movement_demo/scripts/systems/game_state.gd` — currency, awarded tasks, purchases, level entry state, checkpoint fields.
- `movement_demo/scripts/systems/stage/quest_definition.gd` — `money_reward`.
- `movement_demo/scripts/systems/stage/quest_controller.gd` — one-time award on completion.
- `movement_demo/resources/stages/stage_table_template.tres` — five main task rewards.
- `movement_demo/scripts/player/player_weapon_slots.gd` — replace one slot without resetting unrelated state.
- `movement_demo/scripts/world/quest_portal.gd` — save level-entry player state.
- `movement_demo/scripts/systems/scene_director.gd` — use level-entry state on current-level retry.
- `movement_demo/scripts/world/reward_npc.gd` — open the shop through the retained NPC node.
- `movement_demo/scenes/main.tscn` — mount shop board/controller; remove active three-choice wiring.
- `movement_demo/tests/campaign_flow_test.gd` — replace old reward flow with money and shop integration.
- `movement_demo/tests/campaign_quest_task_test.gd` — replace reward eligibility checks with task money checks.
- `movement_demo/tests/campaign_checkpoint_test.gd` — include money/purchased IDs/equipment rollback.
- `movement_demo/tests/scene_director_test.gd` — verify retry uses the level-entry snapshot and hotel rollback remains transactional.
- `movement_demo/tests/run_regressions.py` — register new tests and retire obsolete main-reward suites.
- `README.md`, project/gameplay/testing docs — current behavior and configuration.

**Retire from the current main-flow test catalog**
- `movement_demo/tests/reward_npc_test.gd`
- `movement_demo/tests/reward_per_level_test.gd`
- `movement_demo/tests/quest_encounter_loop_test.gd`

Keep the old reward scripts/resources as compatibility code. Keep `reward_board_test.gd` only if it still exercises the isolated component without requiring shop-era main wiring.

---

### Task 1: Shop Resources and Initial Catalog

**Files:**
- Create: `movement_demo/scripts/shop/shop_item_definition.gd`
- Create: `movement_demo/scripts/shop/shop_catalog.gd`
- Create: `movement_demo/resources/shop/shop_catalog.tres`
- Test: `movement_demo/tests/shop_catalog_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: Godot `Resource`, `WeaponData`.
- Produces:
  - `ShopItemDefinition.Effect` with `HEAL`, `REFILL_AMMO`, `SYSTEM_PROGRESS`, `WEAPON`.
  - `ShopItemDefinition.is_valid() -> bool`.
  - `ShopCatalog.valid_items() -> Array[ShopItemDefinition]`.
  - `ShopCatalog.item_by_id(item_id: StringName) -> ShopItemDefinition`.

- [ ] **Step 1: Write the failing catalog test**

Create `shop_catalog_test.gd` with count checks and literal initial values:

```gdscript
extends SceneTree

const CatalogScript := preload("res://scripts/shop/shop_catalog.gd")
const ItemScript := preload("res://scripts/shop/shop_item_definition.gd")
const Catalog := preload("res://resources/shop/shop_catalog.tres")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var items := Catalog.valid_items()
	print("PASS" if items.size() == 3 else "FAIL", " initial catalog has three products")
	var first: ShopItemDefinition = Catalog.item_by_id(&"first_aid")
	print("PASS" if first.price == 40 and first.effect == ItemScript.Effect.HEAL and first.amount == 35 else "FAIL", " first aid values")
	var gun := ItemScript.new()
	gun.id = &"rifle"
	gun.effect = ItemScript.Effect.WEAPON
	gun.weapon_data = preload("res://resources/weapons/test_rifle.tres")
	gun.one_time = true
	var duplicate := gun.duplicate()
	var catalog = CatalogScript.new()
	catalog.items = [gun, duplicate]
	print("PASS" if catalog.valid_items().size() == 1 else "FAIL", " duplicate IDs are filtered")
	quit(0)
```

Register `"shop_catalog_test"` in `SYSTEM_TESTS`.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_catalog_test.gd
```

Expected: parse/load failure because the shop scripts and catalog do not exist.

- [ ] **Step 3: Implement the resource schema**

Create `ShopItemDefinition` with:

```gdscript
class_name ShopItemDefinition
extends Resource

enum Effect { HEAL, REFILL_AMMO, SYSTEM_PROGRESS, WEAPON }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(0, 999999, 1) var price: int = 0
@export_range(0, 5, 1) var unlock_level: int = 0
@export var effect: Effect = Effect.HEAL
@export_range(0, 9999, 1) var amount: int = 0
@export var weapon_data: WeaponData
@export var one_time: bool = false

func is_valid() -> bool:
	if id == &"" or display_name.is_empty() or price < 0:
		return false
	if effect == Effect.WEAPON:
		return weapon_data != null and one_time
	return effect in [Effect.HEAL, Effect.REFILL_AMMO, Effect.SYSTEM_PROGRESS]
```

Create `ShopCatalog` with ordered `items`, first-ID-wins lookup, and invalid-item diagnostics.

- [ ] **Step 4: Add the initial `.tres` catalog**

Create the three items in `resources/shop/shop_catalog.tres` with exact values:

```text
first_aid: price=40, unlock_level=0, effect=HEAL, amount=35, one_time=false
ammo: price=30, unlock_level=0, effect=REFILL_AMMO, one_time=false
system_progress: price=50, unlock_level=0, effect=SYSTEM_PROGRESS, amount=20, one_time=false
```

- [ ] **Step 5: Run GREEN and commit**

Run the catalog test and expect all checks to pass. Then:

```bash
git add movement_demo/scripts/shop/shop_item_definition.gd movement_demo/scripts/shop/shop_catalog.gd movement_demo/resources/shop/shop_catalog.tres movement_demo/tests/shop_catalog_test.gd movement_demo/tests/shop_catalog_test.gd.uid movement_demo/tests/run_regressions.py
git commit -m "feat: add shop catalog resources"
```

---

### Task 2: Currency, Task Awards, Purchases, and Checkpoints

**Files:**
- Modify: `movement_demo/scripts/systems/game_state.gd`
- Create: `movement_demo/tests/shop_state_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: existing `GameState` checkpoint methods.
- Produces:
  - `money: int`, `money_changed(previous: int, current: int)`.
  - `add_money(amount: int) -> int`.
  - `spend_money(amount: int) -> bool`.
  - `claim_task_reward(task_id: StringName, amount: int, completion_level: int) -> bool`.
  - `has_task_reward(task_id: StringName) -> bool`.
  - `mark_shop_item_purchased(item_id: StringName) -> void`.
  - `has_purchased_shop_item(item_id: StringName) -> bool`.
  - `set_level_entry_player_state(snapshot: Dictionary) -> void`.
  - `prepare_level_retry_state() -> bool`.

- [ ] **Step 1: Write the failing state test**

Test real `GameState` behavior:

```gdscript
var state = preload("res://scripts/systems/game_state.gd").new()
root.add_child(state)
state.money = 100
print("PASS" if state.spend_money(30) and state.money == 70 else "FAIL", " spend persists")
print("PASS" if not state.spend_money(1000) and state.money == 70 else "FAIL", " insufficient funds")
state.completed_level = 1
state.available_level = 1
state.record_campaign_checkpoint(1, {"health": {"health": 50.0}})
print("PASS" if state.claim_task_reward(&"task_a", 100, 1) and state.money == 170 else "FAIL", " task reward once")
print("PASS" if not state.claim_task_reward(&"task_a", 100, 1) and state.money == 170 else "FAIL", " repeated task reward rejected")
state.mark_shop_item_purchased(&"shop_rifle")
state.spend_money(50)
state.money = 20
print("PASS" if state.restore_campaign_checkpoint() and state.money == 170 and not state.has_purchased_shop_item(&"shop_rifle") else "FAIL", " checkpoint refunds post-completion spending")
```

Also assert `record_campaign_checkpoint()` includes `money`, `rewarded_task_ids`, and `purchased_shop_item_ids`, and that `campaign_checkpoint` receives the task reward after the task completes.

- [ ] **Step 2: Run RED**

Run:

```bash
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_state_test.gd
```

Expected: missing methods/fields fail the new assertions.

- [ ] **Step 3: Implement state and checkpoint fields**

Add typed state in `game_state.gd`:

```gdscript
signal money_changed(previous: int, current: int)
var money: int = 0
var rewarded_task_ids: Dictionary = {}
var purchased_shop_item_ids: Dictionary = {}
var level_entry_player_state: Dictionary = {}
```

`add_money` ignores non-positive/non-finite input, clamps at zero, and emits only on change. `spend_money` checks integer positive amount and emits only after successful subtraction.

`claim_task_reward` performs these operations once:

```gdscript
if amount <= 0 or task_id == &"" or has_task_reward(task_id):
	return false
rewarded_task_ids[task_id] = true
var previous := money
money += amount
money_changed.emit(previous, money)
if not campaign_checkpoint.is_empty() \
		and int(campaign_checkpoint.get("completed_level", -1)) == completion_level \
		and not bool(campaign_checkpoint.get("rewarded_task_ids", {}).get(task_id, false)):
	campaign_checkpoint["rewarded_task_ids"][task_id] = true
	campaign_checkpoint["money"] = int(campaign_checkpoint.get("money", 0)) + amount
return true
```

Add the new fields to `record_campaign_checkpoint()` and `capture_campaign_state()`. Restore them in `restore_campaign_state()`; old checkpoints without fields default to `0`/empty dictionaries.

`set_level_entry_player_state()` deep-copies the snapshot. `prepare_level_retry_state()` copies it into `pending_player_state` and returns whether a snapshot existed.

- [ ] **Step 4: Run GREEN and commit**

Run `shop_state_test` and the existing `campaign_checkpoint_test`; both must pass. Then:

```bash
git add movement_demo/scripts/systems/game_state.gd movement_demo/tests/shop_state_test.gd movement_demo/tests/shop_state_test.gd.uid
git commit -m "feat: add currency and checkpoint purchase state"
```

---

### Task 3: Fixed Task Money

**Files:**
- Modify: `movement_demo/scripts/systems/stage/quest_definition.gd`
- Modify: `movement_demo/scripts/systems/stage/quest_controller.gd`
- Modify: `movement_demo/resources/stages/stage_table_template.tres`
- Modify: `movement_demo/tests/campaign_quest_task_test.gd`
- Create: `movement_demo/tests/quest_money_reward_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: `GameState.claim_task_reward(task_id, amount, completion_level)`.
- Produces: `QuestDefinition.money_reward: int`.

- [ ] **Step 1: Write the failing task-money test**

Use the real main scene and `GameState`:

```gdscript
state.money = 0
state.rewarded_task_ids = {}
state.help_choice = "accepted"
state.completed_level = 1
await process_frame
await process_frame
print("PASS" if state.money == 100 else "FAIL", " task completion pays 100")
state.completed_level = 0
state.completed_level = 1
await process_frame
print("PASS" if state.money == 100 else "FAIL", " task reward does not repeat")
```

Add a second assertion that `QuestDefinition.new().money_reward == 100` and that the saved five main quest resources expose `100`.

- [ ] **Step 2: Run RED**

Run the new test. Expected: the defaulted reward amount is missing or wrong.

- [ ] **Step 3: Implement task payout**

Add `@export_range(0, 999999, 1) var money_reward: int = 100` to `QuestDefinition`.

In `QuestController.set_status()`, after assigning `_statuses[quest_id]`, call payout only when entering `COMPLETED`:

```gdscript
if status == Status.COMPLETED:
	var definition := quest_definition(quest_id)
	if definition != null and definition.money_reward > 0 and _state != null \
			and _state.has_method(&"claim_task_reward"):
		_state.claim_task_reward(quest_id, definition.money_reward, int(_state.get(&"completed_level")))
```

Set `money_reward = 100` on `Quest_task_a` and `Quest_task_level_2` through `Quest_task_level_5`. Leave `Quest_task_music` explicit at `0`.

- [ ] **Step 4: Update task-chain assertions**

Replace old reward-claim assertions in `campaign_quest_task_test` with checks for exactly `100` money per newly completed main task and no duplicate on reevaluation.

- [ ] **Step 5: Run GREEN and commit**

Run `quest_money_reward_test`, `campaign_quest_task_test`, and `shop_state_test`. Then:

```bash
git add movement_demo/scripts/systems/stage/quest_definition.gd movement_demo/scripts/systems/stage/quest_controller.gd movement_demo/resources/stages/stage_table_template.tres movement_demo/tests/quest_money_reward_test.gd movement_demo/tests/quest_money_reward_test.gd.uid movement_demo/tests/campaign_quest_task_test.gd movement_demo/tests/run_regressions.py
git commit -m "feat: pay fixed task rewards once"
```

---

### Task 4: Weapon Slot Replacement and Current-Level Retry

**Files:**
- Modify: `movement_demo/scripts/player/player_weapon_slots.gd`
- Modify: `movement_demo/scripts/world/quest_portal.gd`
- Modify: `movement_demo/scripts/systems/scene_director.gd`
- Create: `movement_demo/tests/shop_weapon_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: `Equipment.campaign_snapshot()` and `apply_campaign_snapshot()`.
- Produces:
  - `Equipment.replace_weapon_slot(slot: int, weapon: WeaponData) -> bool`.
  - `GameState.level_entry_player_state`.
  - Current-level retry preserves the paid level-entry loadout.

- [ ] **Step 1: Write the failing equipment/retry test**

Instantiate the real main scene and player:

```gdscript
var equipment = scene.get_node("Player/Equipment")
var original_primary := equipment.primary_weapon
var original_reserve := equipment.reserve_ammo.duplicate()
print("PASS" if equipment.replace_weapon_slot(0, load("res://resources/weapons/test_shotgun.tres")) else "FAIL", " replace primary")
print("PASS" if equipment.primary_weapon.display_name == "测试霰弹枪" and equipment.reserve_ammo == original_reserve else "FAIL", " replacement preserves reserve")
equipment.replace_weapon_slot(0, original_primary)
state.set_level_entry_player_state(equipment.campaign_snapshot())
equipment.replace_weapon_slot(0, load("res://resources/weapons/test_smg.tres"))
state.prepare_level_retry_state()
print("PASS" if state.pending_player_state != equipment.campaign_snapshot() else "FAIL", " retry snapshot is independent")
```

Add a real-level death/retry case that buys/replaces a weapon before entering Level 2 and asserts the retry player has that weapon.

- [ ] **Step 2: Run RED**

Run:

```bash
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_weapon_test.gd
```

Expected: `replace_weapon_slot` missing and retry loses the paid loadout.

- [ ] **Step 3: Implement slot replacement**

Add:

```gdscript
func replace_weapon_slot(slot: int, weapon: WeaponData) -> bool:
	if slot not in [0, 1] or weapon == null or weapon.fire_mode == WeaponData.FireMode.MELEE:
		return false
	var snapshot := campaign_snapshot()
	if slot == 0:
		snapshot["primary_weapon"] = weapon
	else:
		snapshot["secondary_weapon"] = weapon
	var magazines: Array = snapshot["magazines"]
	magazines[slot] = weapon.magazine_capacity
	snapshot["magazines"] = magazines
	apply_campaign_snapshot(snapshot)
	return _weapon_at(slot) == weapon
```

Update display and active combat binding through the existing `apply_campaign_snapshot()` path.

- [ ] **Step 4: Capture and reuse level-entry state**

In `QuestPortal.interact()`, after capturing the campaign snapshot:

```gdscript
_game_state.set_level_entry_player_state(snapshot)
```

In `SceneDirector.request_restart()`, before `_start_load("", true)`:

```gdscript
var game_state := get_node_or_null("/root/GameState")
if game_state != null and game_state.has_method(&"prepare_level_retry_state"):
	game_state.prepare_level_retry_state()
```

Keep transactional hotel rollback unchanged.

- [ ] **Step 5: Run GREEN and commit**

Run `shop_weapon_test`, `weapon_slots_test`, `scene_director_test`, and `campaign_flow_test`. Then commit the focused files with:

```bash
git commit -m "feat: preserve purchased loadout on level retry"
```

---

### Task 5: Shop Board, Controller, and Blue NPC Entry

**Files:**
- Create: `movement_demo/scenes/ui/shop_board.tscn`
- Create: `movement_demo/scripts/ui/shop_board.gd`
- Create: `movement_demo/scripts/shop/shop_controller.gd`
- Modify: `movement_demo/scripts/world/reward_npc.gd`
- Modify: `movement_demo/scenes/main.tscn`
- Create: `movement_demo/tests/shop_board_test.gd`
- Create: `movement_demo/tests/shop_flow_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`

**Interfaces:**
- Consumes: `ShopCatalog.valid_items()`, `GameState` money/purchase methods, `Equipment.replace_weapon_slot()`.
- Produces:
  - `ShopController.open_shop_for_player(player: Node3D) -> bool`.
  - `ShopController.purchase(item_id: StringName, slot: int) -> bool`.
  - `ShopController.close_shop() -> void`.
  - `ShopBoard.configure(items: Array[Dictionary], money: int) -> bool`.
  - `ShopBoard.purchase_requested(item_id: StringName, slot: int)`.
  - `ShopBoard.item_count() -> int`.

- [ ] **Step 1: Write the failing board test**

Instantiate `shop_board.tscn`, configure three literal view dictionaries, and assert:

```gdscript
print("PASS" if board.item_count() == 3 else "FAIL", " three rows")
print("PASS" if board.balance_text() == "货币：100" else "FAIL", " balance")
print("PASS" if board.press_purchase(&"ammo", -1) else "FAIL", " purchase intent")
print("PASS" if board.last_purchase == {&"item_id": &"ammo", &"slot": -1} else "FAIL", " exact intent")
```

Add level-hidden and weapon-slot-row assertions using view dictionaries with `weapon=true`.

- [ ] **Step 2: Run RED**

Run `shop_board_test`; expected missing scene/script.

- [ ] **Step 3: Build the dynamic board**

Create a scene with stable paths:

```text
ShopBoard
└─ Backdrop
   └─ Center
      └─ Panel
         └─ Margin
            └─ Content
               ├─ Header/Title
               ├─ Header/Balance
               ├─ Scroll/Items
               ├─ Result
               └─ Close
```

`shop_board.gd` builds one row per view dictionary. Consumables get one purchase button. Weapon rows get primary and secondary buttons that emit slot `0`/`1`. The board only emits requests and closes; it never mutates game state.

- [ ] **Step 4: Implement the purchase controller**

`ShopController` filters visible products:

```gdscript
func _is_visible(item: ShopItemDefinition) -> bool:
	if item.unlock_level > int(_state.get(&"completed_level")):
		return false
	return not item.one_time or not _state.has_purchased_shop_item(item.id)
```

Purchase sequence:

1. Revalidate item, visibility, balance, effect and optional slot.
2. For `WEAPON`, call `Equipment.replace_weapon_slot(slot, item.weapon_data)`.
3. For `HEAL`, call `Health.heal(item.amount)` only when life is below max.
4. For `REFILL_AMMO`, call `Equipment.refill_all_ammo()`.
5. For `SYSTEM_PROGRESS`, call `GameState.add_system_progress(item.amount)` only below 100.
6. Spend exactly once.
7. Mark one-time purchase and refresh the visible rows.

If any pre-effect validation fails, return false without spending or marking.

- [ ] **Step 5: Reuse the blue NPC and wire main**

Change `reward_npc.gd` to export `shop_controller_path := ^"../ShopController"` and call `open_shop_for_player(player)`.

In `main.tscn`:

- Change `RewardNPC/Name.text` to `商店`.
- Add `ShopBoard` instance and `ShopController` node.
- Point `shop_catalog` to `resources/shop/shop_catalog.tres`.
- Remove active `RewardBoard` and `EncounterController` nodes from main.
- Keep `RewardNPC` node path unchanged.

- [ ] **Step 6: Write real shop-flow tests**

`shop_flow_test` must cover:

- E interaction opens the shop and pauses.
- Initial three rows are present at completed level 0.
- Buying `first_aid` heals 35, buying `ammo` refills both magazines and initial reserve ammo, and buying `system_progress` adds 20.
- A second purchase of any repeatable item is allowed when funds/effect remain available.
- A manually added weapon shop item remains hidden until its `unlock_level`.
- Buying the weapon into slot 0 deducts currency, changes the weapon, and hides the one-time row.
- Buying into slot 1 works independently.
- Insufficient funds, repeat-purchase, and invalid slot do not mutate state.
- Closing the board releases only the shop-owned pause token.
- Missing player, missing board, missing catalog, and an empty catalog fail without pausing or mutating state.

- [ ] **Step 7: Run GREEN and commit**

Run `shop_board_test`, `shop_flow_test`, `reward_board_test`, `player_health_test`, and `weapon_slots_test`. Then:

```bash
git commit -m "feat: replace reward choice with currency shop"
```

---

### Task 6: Campaign Death Refund and Retry Integration

**Files:**
- Modify: `movement_demo/tests/campaign_flow_test.gd`
- Modify: `movement_demo/tests/campaign_checkpoint_test.gd`
- Modify: `movement_demo/tests/scene_director_test.gd`
- Modify: `movement_demo/tests/run_regressions.py`
- Retire: old main-flow reward tests listed in File Structure.

**Interfaces:**
- Consumes: all earlier shop, money, checkpoint, equipment, retry interfaces.
- Produces: end-to-end proof that spending and equipment roll back together.

- [ ] **Step 1: Convert campaign flow from rewards to money**

Remove `RewardBoard`, `EncounterController`, and old claim assertions. Add real checks:

```gdscript
check(state.money == 100, "第1关完成获得100")
check(shop.interact(player) or shop.open_shop_for_player(player), "蓝色NPC打开商店")
check(shop_controller.purchase(&"ammo", -1), "购买弹药")
check(state.money == 70, "购买后扣款")
```

Enter Level 2, die, and retry current; assert the entry loadout remains.

Enter again, buy a one-time weapon, enter Level 2, die, and return to the hotel; assert:

- money and purchase ID return to checkpoint values;
- the previous slot weapon is restored;
- the one-time weapon row is visible again;
- the task's 100 award is not duplicated.

Also assert the completion checkpoint itself contains the 100 award even though the return portal recorded it before the tavern task controller completed the task.

- [ ] **Step 2: Update checkpoint tests**

Replace old reward-claim fields with money, rewarded task IDs, purchased item IDs, system progress, and player snapshot. Assert old checkpoint dictionaries without new fields restore safely to defaults.

- [ ] **Step 3: Update scene-director retry tests**

Add a fixture snapshot with a paid weapon in slot 0. Verify:

- current-level restart sets `pending_player_state` from `level_entry_player_state`;
- hotel failure rollback still prevents checkpoint contamination;
- a failed hotel attempt followed by retry uses the level-entry snapshot, not checkpoint currency/equipment.

- [ ] **Step 4: Retire obsolete main reward tests**

Remove `reward_npc_test`, `reward_per_level_test`, and `quest_encounter_loop_test` from the active systems catalog. Delete those files because their tested main flow no longer exists; keep the compatibility scripts/resources.

Run:

```bash
python3 movement_demo/tests/run_regressions.py --check
```

Expected: `Catalog OK`.

- [ ] **Step 5: Run the full focused suite**

Run:

```bash
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_catalog_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_state_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_weapon_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_board_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_flow_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/campaign_flow_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/campaign_checkpoint_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/scene_director_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/level_flow_test.gd
```

All must exit `0`; inspect logs for unexpected script errors.

- [ ] **Step 6: Commit**

```bash
git add movement_demo/tests/campaign_flow_test.gd movement_demo/tests/campaign_checkpoint_test.gd movement_demo/tests/scene_director_test.gd movement_demo/tests/run_regressions.py
git commit -m "test: verify shop and death checkpoint consistency"
```

---

### Task 7: Documentation and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/project-layout.md`
- Modify: `docs/gameplay/INTERACTION.md`
- Modify: `docs/gameplay/STAGE_STATE.md`
- Modify: `docs/gameplay/PLAY_GUIDE.md`
- Modify: `docs/gameplay/REWARDS.md`
- Modify: `docs/gameplay/PLAYER_HEALTH.md`
- Modify: `docs/gameplay/AMMO.md`
- Modify: `docs/testing.md`
- Modify: `docs/TODO.md`

**Interfaces:**
- Consumes: verified implementation behavior.
- Produces: accurate editor and player documentation.

- [ ] **Step 1: Update user-facing docs**

Document:

- Blue NPC opens shop.
- Prices, hidden unlock rules, task money, retry preservation, hotel refund.
- How to add a `ShopItemDefinition` and bind an existing `WeaponData`.
- Old three-choice is no longer the main flow.

- [ ] **Step 2: Update maintenance docs**

Document new files, state ownership, checkpoint fields, task reward synchronization, and compatibility components.

- [ ] **Step 3: Record exact test evidence**

Update `docs/testing.md` with direct suite counts, exit codes, and known macOS certificate/resource warnings. Do not claim the full systems group is clean without evidence.

- [ ] **Step 4: Run final verification**

```bash
git diff --check
python3 movement_demo/tests/run_regressions.py --check
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_catalog_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_state_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_weapon_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_board_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/shop_flow_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/campaign_flow_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/campaign_checkpoint_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/scene_director_test.gd
/Users/wzy/Downloads/Godot.app/Contents/MacOS/Godot --headless --path movement_demo --script res://tests/level_flow_test.gd
```

- [ ] **Step 5: Review, commit, and push**

Run the code-review skill after implementation. Stage only this feature's files, exclude the unrelated `.textClipping` artifact, commit the documentation/final fixes, and push `wzy/dev`.
