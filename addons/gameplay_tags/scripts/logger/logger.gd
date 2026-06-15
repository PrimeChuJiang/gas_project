# 日志器
@tool

class_name GameplayTagsLogger

enum LogLevel {
	INFO,
	DEBUG,
	WARNING,
	ERROR,
}

# 打印日志
static func print_log(level : LogLevel = LogLevel.DEBUG, header : String = "", message : String = "default log") -> void:
	var log_string : String;
	match level:
		LogLevel.INFO:
			log_string = set_string_color("gray", "[INFO]");
		LogLevel.DEBUG:
			log_string = set_string_color("green", "[DEBUG]");
		LogLevel.WARNING:
			log_string = set_string_color("yellow", "[WARNING]");
		LogLevel.ERROR:
			log_string = set_string_color("red", "[ERROR]");
		_:
			log_string = set_string_color("white", "[UNKNOWN]");
	print_rich(log_string + " " + header + " :" + message);

# 设置字符串颜色(富文本)
static func set_string_color(color, text : String) -> String:
	if not color or color == "":
		return text;
	if color is Color:
		return "[color=" + color.to_html() + "]" + text + "[/color]";
	if color is String:
		return "[color=" + color + "]" + text + "[/color]";
	return text;

