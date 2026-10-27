extends CanvasLayer

## 五关共用的入场说明；仅在显示期间持有暂停，关闭或退树时恢复原状态。
const GUIDE_TEXT := """[b][color=#8ed9e8]01  移动与掩体[/color][/b]
[b]W / A / S / D[/b] 按画面方向移动；换方向时角色需要转身，并有加减速。
[b]按住 Shift[/b] 奔跑，消耗体力。耗尽后要回满才能再次奔跑；松开后可恢复。
[b]C[/b] 切换蹲下／站起。蹲行更慢、脚步更轻，瞄准散布更小。
[b]空格[/b] 翻越面前的半身掩体，需要安全落点；翻越时不能攻击，仍会受伤。
蹲在矮墙后，向墙外瞄准会临时起身，松开右键回蹲；此时按 C 可改为保持站立。

[b][color=#8ed9e8]02  瞄准与交火[/color][/b]
进入战斗区域后，[b]按住鼠标右键[/b] 瞄准，自动锁定角色朝向附近、范围内且可见的敌人，并持续跟踪。
[b]锁定时朝另一名敌人所在的屏幕方向拨动鼠标[/b]，即可切换目标，无需把光标放在敌人身上。相邻目标轻拨、远处目标多拨一点；切换后继续移动鼠标可接着换锁，无需停顿。该方向没有合适目标时保持原锁定。
换锁后角色会平滑转向，转得越多、目标越远，跟枪精度损耗越大。转身中也能立即开枪，按当时朝向和准度射出，未对准时可能打偏。
浅蓝色“转向中”标记只表示下一个目标；对准后才恢复普通准星和爆头菱形。
[b]右键瞄准时按左键[/b] 开火：单发／霰弹每次点击一枪，自动武器可按住连射。
停步、减少连射可让准星收拢；移动、跟枪、开火、受击或近弹压制会干扰精度。锁定不保证命中，墙体会挡子弹。
[b]精度达到一定程度后，实际命中就有概率爆头；精度越高，爆头概率越大。[/b]金色菱形出现后随概率升高收小，满精准时发光，实际命中必爆头；秒杀仍取决于武器和敌人防护。
[b]V[/b] 向当前朝向近战，消耗体力；瞄准时朝瞄准方向挥击，适合应对贴身敌人。
[b]近战命中可让敌人短暂眩晕，提高对该敌人的爆头概率。[/b]头顶星环表示眩晕尚未结束；爆头加成在首次枪击命中后消耗，打空不消耗，眩晕结束也会失效。

[b][color=#8ed9e8]03  切枪、换弹与补给[/color][/b]
[b]1 / 2[/b] 选择主／副武器，[b]鼠标滚轮[/b] 切换。右下角查看各枪弹匣与共享备弹。
[b]R[/b] 主动换弹，空匣不会自动装填；换弹期间不能射击。
普通整匣换弹：非奔跑时开始较快；中途奔跑或切枪，未到半程会取消，达到半程则保留 50%，条件允许后自动续换。奔跑中按 R 开始较慢，但可边跑边换。
若武器启用逐发装填，已装入的子弹会保留，可新按右键中断；其余规则看当前武器提示。
携带弹药不足半匣时，击杀敌人可获得最缺弹种的补给；靠近自动拾取，拾取后仍需按 R 装填。每区地面最多两包。

[b][color=#8ed9e8]04  治疗与过关[/color][/b]
[b]H[/b] 使用医疗包：先松开移动、瞄准等动作键；治疗需要时间，动作输入或受击会打断，中断不消耗。
利用掩体换弹和治疗，留意左下角生命与体力。敌人会听声音、搜索和配合，不要长时间暴露。
清空本关全部波次后，点击[b]进入下一关[/b]继续；每关按各自配置重新准备生命、武器与弹药。
死亡后可重开当前关；第 5 关结束显示通关界面，可从第 1 关重新挑战。"""

@onready var _body: RichTextLabel = $Backdrop/Panel/Content/Body
@onready var _close_button: Button = $Backdrop/Panel/Content/Close

var _owns_pause := false
var _previous_pause := false
var _previous_mouse_mode: Input.MouseMode


func _ready() -> void:
	_body.text = GUIDE_TEXT
	_close_button.pressed.connect(close_guide)
	_previous_pause = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	# 先让战斗收到暂停并释放临时捕获，再记录界面关闭后应恢复的模式。
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_close_button.grab_focus()


func close_guide() -> void:
	if not visible: return
	hide()
	_close_button.release_focus()
	_restore_state()


func _exit_tree() -> void:
	_restore_state()


func _restore_state() -> void:
	if not _owns_pause: return
	_owns_pause = false
	get_tree().paused = _previous_pause
	Input.mouse_mode = _previous_mouse_mode
