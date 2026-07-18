# 日志器
@tool
class_name GameLogger
## 日志工具
## 
## 日志支持多种调用方式，最常用的几个函数为info(), debug(), warn(), error()
## 外部类调用方式如下：
## # 声明Log等级enum数据结构
## const LL := GameLogger.LogLevel
## 
## func func_name() -> void: # 在任意函数内调用
## 	var script_self : Script = self.get_script() # 获取代码对象
## 	GameLogger.info(script_self.get_global_name(), "这是一条INFO消息", true) # script_self.get_global_name()用于获取自定义类名称
## 	GameLogger.debug(script_self.get_global_name(), ["这是一条DEBUG消息", "，同时这也是一个数组", 123], true)
## 	GameLogger.warn(script_self.get_global_name(), "这是一条WARNING消息", true)
## 	GameLogger.error(script_self.get_global_name(), "这是一条ERROR消息", true)
## 得到的消息结果如下：
## [INFO][15:33:24][ScriptName]:这是一条INFO消息
## [DEBUG][15:33:24][ScriptName]:这是一条DEBUG消息，同时这也是一个数组123
## [WARNING][15:33:24][ScriptName]:这是一条WARNING消息
## [ERROR][15:33:24][ScriptName]:这是一条ERROR消息



# 等级按「严重度递增」排列，这样 min_level 过滤才符合直觉
enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR,
}

# ───────────────────────── 全局配置（运行时可改）─────────────────────────

# 全局日志等级门槛：低于此等级的日志直接丢弃
static var min_level : LogLevel = LogLevel.DEBUG

# 是否把日志写入文件
static var log_to_file : bool = true

# 日志文件路径（user:// 在 Windows 下是 %APPDATA%\Godot\app_userdata\项目名\）
const LOG_FILE_PATH := "user://game.log"

# 每个等级对应的颜色与文字标签，集中配置便于统一换主题
const LEVEL_COLORS := {
	LogLevel.DEBUG: "green",
	LogLevel.INFO: "gray",
	LogLevel.WARNING: "yellow",
	LogLevel.ERROR: "red",
}
const LEVEL_LABELS := {
	LogLevel.DEBUG: "[DEBUG]",
	LogLevel.INFO: "[INFO]",
	LogLevel.WARNING: "[WARNING]",
	LogLevel.ERROR: "[ERROR]",
}

# 文件句柄（懒加载，第一次写入时打开）
static var _file : FileAccess


# ───────────────────────── 核心打印 ─────────────────────────

# show_caller: 为 true 时在末尾附上「脚本文件:行号」（仅 debug 构建有堆栈信息）
static func print_log(level : LogLevel = LogLevel.DEBUG, header : StringName = "", messages = "", show_time : bool = true, show_caller : bool = false) -> void:
	# 1. 全局等级过滤
	if level < min_level:
		return

	# 2. Release 构建里 DEBUG 直接空转（更严重的等级仍保留，方便线上排错）
	if level == LogLevel.DEBUG and not OS.is_debug_build():
		return

	# 3. 组装正文纯文本（供文件与调试器复用）
	var body := "[" + header + "]:"
	if messages is String:
		body += messages
	elif messages is Array:
		for m in messages:
			body += str(m)
	else:
		body += str(messages)

	# 4. 调用位置（可选）
	var caller_str := ""
	if show_caller and OS.is_debug_build():
		caller_str = _get_caller_location()

	# 5. 时间戳
	var time_str := ""
	if show_time:
		time_str = "[" + Time.get_time_string_from_system(true) + "]"

	var label : String = LEVEL_LABELS.get(level, "[UNKNOWN]")

	# 6. 富文本输出到控制台
	var colored : String = set_string_color(LEVEL_COLORS.get(level, "white"), label)
	print_rich(colored + time_str + body + caller_str)

	# 7. 纯文本版本：接入调试器 + 写文件
	var plain : String = label + time_str + body + caller_str
	match level:
		LogLevel.WARNING:
			push_warning(plain)
		LogLevel.ERROR:
			push_error(plain)

	# 8. 写入文件
	if log_to_file:
		_write_to_file(plain)


# 从调用栈里找出第一个「不是本日志器」的帧，避免定位到 print_log / info / debug 自己
static func _get_caller_location() -> String:
	var stack := get_stack()
	for frame in stack:
		var src := String(frame.get("source", ""))
		if src != "" and not src.ends_with("logger.gd"):
			return " (%s:%d)" % [src.get_file(), frame.get("line", 0)]
	return ""


static func _write_to_file(line : String) -> void:
	if _file == null:
		_open_log_file()
	if _file:
		_file.store_line(line)
		_file.flush()  # 逐行 flush，保证崩溃时日志不丢


# 以「追加」方式打开日志文件，保留历史；并写一行会话分隔标记
static func _open_log_file() -> void:
	if FileAccess.file_exists(LOG_FILE_PATH):
		# 文件已存在：用 READ_WRITE 打开后跳到末尾，旧内容不会被清空
		_file = FileAccess.open(LOG_FILE_PATH, FileAccess.READ_WRITE)
		if _file:
			_file.seek_end()
	else:
		# 文件不存在：WRITE 创建一个新文件
		_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)

	if _file:
		# 每次启动写一条分隔，方便在长日志里区分不同会话
		_file.store_line("")
		_file.store_line("==== 会话开始 %s ====" % Time.get_datetime_string_from_system(true, true))
		_file.flush()


# 设置字符串颜色(富文本)
static func set_string_color(color, text : String) -> String:
	if color is Color:
		# bbcode 的十六进制颜色需要 # 前缀
		return "[color=#" + color.to_html() + "]" + text + "[/color]"
	if color is String and color != "":
		return "[color=" + color + "]" + text + "[/color]"
	return text


# ───────────────────────── 便捷方法 ─────────────────────────

static func info(header : String, messages, show_caller : bool = false):
	print_log(LogLevel.INFO, header, messages, true, show_caller)

static func debug(header : String, messages, show_caller : bool = false):
	print_log(LogLevel.DEBUG, header, messages, true, show_caller)

static func warn(header : String, messages, show_caller : bool = false):
	print_log(LogLevel.WARNING, header, messages, true, show_caller)

static func error(header : String, messages, show_caller : bool = false):
	print_log(LogLevel.ERROR, header, messages, true, show_caller)
