-- ============================================================
-- WezTerm 配置文件
-- 用途: 主要用于 Claude Code 开发
-- ============================================================

local wezterm = require("wezterm")
local config = wezterm.config_builder()
local mux = wezterm.mux

-- ============================================================
-- 调试日志函数 (必须在其他函数之前定义)
-- ============================================================
local function log_debug(msg)
	local f = io.open(os.getenv("HOME") .. "/.cache/wezterm/debug.log", "a")
	if f then
		f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
		f:close()
	end
end

-- ============================================================
-- 窗口颜色分配 (每个窗口不同底部线颜色)
-- ============================================================
local WINDOW_BORDER_COLORS = {
	"#ff0000", -- ① 红
	"#00ff00", -- ② 绿
	"#0088ff", -- ③ 蓝
	"#ff8800", -- ④ 橙
	"#ff00ff", -- ⑤ 紫
	"#00ffff", -- ⑥ 青
	"#ffff00", -- ⑦ 黄
	"#ff4488", -- ⑧ 粉
}

-- 为窗口分配颜色(基于窗口ID，确定性分配，配置重载不影响)
local function assign_window_color(window_id)
	-- 使用窗口ID对颜色数量取模，确保每个窗口颜色固定且循环使用
	local index = ((window_id - 1) % #WINDOW_BORDER_COLORS) + 1
	return WINDOW_BORDER_COLORS[index]
end

-- ============================================================
-- 启动时自动全屏 + 设置窗口边框颜色
-- 使用 window-focus-changed 事件确保 GUI 就绪后执行
-- ============================================================

-- ① 使用非原生全屏模式（快速、无 Space 切换动画）
config.native_macos_fullscreen_mode = false

-- ② 启动时自动全屏（使用窗口聚焦事件，确保只执行一次）
local fullscreen_initialized = {}
wezterm.on("window-focus-changed", function(window, pane)
	local window_id = window:window_id()
	if not fullscreen_initialized[window_id] then
		fullscreen_initialized[window_id] = true
		window:toggle_fullscreen()
	end
end)

-- ③ 设置窗口底部边框颜色
wezterm.on("update-status", function(window, pane)
	local window_id = window:window_id()
	local overrides = window:get_config_overrides() or {}
	if not overrides.window_frame then
		local color = assign_window_color(window_id)
		overrides.window_frame = {
			border_left_width = "0px",
			border_right_width = "0px",
			border_top_height = "0px",
			border_bottom_height = "3px",
			border_bottom_color = color,
			active_titlebar_border_bottom = color,
		}
		window:set_config_overrides(overrides)
	end
end)

-- ============================================================
-- 新建 tab 紧挨当前 tab (而非追加到末尾)
-- ============================================================
wezterm.on("spawn-tab-next-to-current", function(window, pane)
	log_debug("spawn-tab-next-to-current triggered")

	-- 获取 mux window 对象
	local mux_window = window:mux_window()
	log_debug("got mux_window")

	-- 使用 tabs_with_info 获取带索引信息的 tab 列表
	local tabs_with_info = mux_window:tabs_with_info()
	log_debug("tabs count: " .. #tabs_with_info)

	local current_idx = 0
	-- 找到当前活动 tab 的索引
	for i, t in ipairs(tabs_with_info) do
		if t.is_active then
			current_idx = i - 1 -- 转为 0-based
			log_debug("found active tab at index: " .. current_idx)
			break
		end
	end

	-- 新建 tab (默认追加到末尾)
	mux_window:spawn_tab({})
	log_debug("spawned new tab")

	-- 计算新 tab 当前在末尾的索引
	local new_tab_idx = #tabs_with_info -- 0-based (因为刚新建了一个)

	-- 计算需要移动的距离: 移动到当前 tab 的右边
	local offset = current_idx + 1 - new_tab_idx
	log_debug("offset: " .. offset)

	-- 执行移动
	if offset ~= 0 then
		window:perform_action(wezterm.action.MoveTabRelative(offset), pane)
		log_debug("moved tab")
	end
end)

-- ============================================================
-- Claude Code 兼容性
-- ============================================================
-- 启用 Kitty 键盘协议，支持复杂的键盘组合键（Claude Code 必需）
config.enable_kitty_keyboard = true

-- ============================================================
-- 关闭窗口确认
-- ============================================================
config.window_close_confirmation = "NeverPrompt"

-- ============================================================
-- 双字体配置 (按 F12 切换)
-- ============================================================
local FONT_PROFILES = {
	-- 手写体: 适合阅读/休闲使用
	{
		name = "手写体",
		font = wezterm.font("SueEllenFrancisco Nerd Font"),
		font_size = 22.0,
	},
	-- 等宽体: 适合编程/Claude Code
	{
		name = "等宽体",
		font = wezterm.font("DaddyTimeMono Nerd Font"),
		font_size = 16.0,
	},
}

-- 当前使用的字体配置索引 (1-based, 循环切换)
local current_font_idx = 1

-- 字体切换函数 (循环切换)
local function toggle_font_profile(window, pane)
	current_font_idx = current_font_idx % #FONT_PROFILES + 1
	local profile = FONT_PROFILES[current_font_idx]

	window:set_config_overrides({
		font = profile.font,
		font_size = profile.font_size,
	})

	window:toast_notification("字体已切换", profile.name, nil, 2000)
end

-- ============================================================
-- 快捷键配置
-- ============================================================
-- Cmd+Enter  全屏切换
-- F12        切换字体方案
-- Cmd+↑/↓    滚动到顶部/底部
-- Cmd+T      新建 tab
-- Cmd+W      关闭 tab
-- ============================================================
-- 鼠标绑定 (Alt+滚轮切换标签页)
-- ============================================================
config.mouse_bindings = {
	{
		event = { Down = { streak = 1, button = { WheelUp = 1 } } },
		mods = "ALT",
		action = wezterm.action.ActivateTabRelative(-1),
	},
	{
		event = { Down = { streak = 1, button = { WheelDown = 1 } } },
		mods = "ALT",
		action = wezterm.action.ActivateTabRelative(1),
	},
}

config.keys = {
	-- code agent 使用 Shift+Enter 发送换行符
	{ key = "Enter", mods = "SHIFT", action = wezterm.action.SendString("\n") },
	{ key = "F12", mods = "", action = wezterm.action_callback(toggle_font_profile) },
	-- 滚动快捷键
	{ key = "UpArrow", mods = "CMD", action = wezterm.action.ScrollToTop },
	{ key = "DownArrow", mods = "CMD", action = wezterm.action.ScrollToBottom },
	-- Tab 管理
	{ key = "t", mods = "CMD", action = wezterm.action.EmitEvent("spawn-tab-next-to-current") },
	{ key = "w", mods = "CMD", action = wezterm.action.CloseCurrentTab({ confirm = false }) },
	-- Tab 相对位置切换 (覆盖默认的 Cmd+1/2)
	{ key = "1", mods = "CMD", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "2", mods = "CMD", action = wezterm.action.ActivateTabRelative(1) },
	{ key = "F2", mods = "", action = wezterm.action.ActivateCopyMode },
}

-- ============================================================
-- 默认字体设置 (使用手写体)
-- ============================================================
config.font = FONT_PROFILES[1].font
config.font_size = FONT_PROFILES[1].font_size

-- 关闭反锯齿，呈现锐利的像素边缘
config.freetype_load_flags = "NO_HINTING|MONOCHROME"
config.freetype_load_target = "Mono"
config.freetype_render_target = "Mono"

-- 允许方块字形溢出单元格，改善 ASCII 图表对齐
config.allow_square_glyphs_to_overflow_width = "Always"

-- ============================================================
-- Tab 标签样式
-- 活动标签: 实心圆 ●
-- 非活动标签: 空心圆 ○
-- 根据工作目录分配不同的绿色饱和度
-- ============================================================

-- 路径到颜色的缓存
local path_color_cache = {}

-- 预定义的颜色 (绿、品红、蓝色基调)
local GREEN_PALETTE = {
	"#00ff00", -- 纯绿
	"#ff00ff", -- 纯品红
	"#00aaff", -- 亮蓝
	"#00dd00", -- 深绿
	"#ff88ff", -- 浅品红
	"#0088ff", -- 中蓝
	"#66ff66", -- 浅绿
	"#dd00dd", -- 深品红
	"#0055dd", -- 深蓝
	"#00aa55", -- 橄榄绿
}

-- 简单的字符串哈希函数 (djb2)
local function hash_string(str)
	local hash = 5381
	for i = 1, #str do
		hash = ((hash << 5) + hash) + str:byte(i)
	end
	return math.abs(hash)
end

-- 从 URL 中提取路径
local function get_path_from_url(url)
	if not url then
		return nil
	end

	-- 如果是 wezterm 的 Url 对象 (userdata 类型，有 file_path 属性)
	if url.file_path then
		return url.file_path
	end

	-- 如果是字符串，解析 URL
	if type(url) == "string" then
		local path = url:gsub("^file://", "")
		-- URL 解码
		path = path:gsub("%%(%x%x)", function(hex)
			return string.char(tonumber(hex, 16))
		end)
		return path
	end

	return nil
end

-- 根据路径获取颜色 (相同路径始终返回相同颜色，基于哈希)
local function get_color_for_path(path)
	if not path or path == "" or path == "~" then
		return GREEN_PALETTE[1]
	end

	-- 使用哈希确保相同路径总是获得相同颜色
	if not path_color_cache[path] then
		local hash = hash_string(path)
		local index = (hash % #GREEN_PALETTE) + 1
		path_color_cache[path] = GREEN_PALETTE[index]
	end

	return path_color_cache[path]
end

-- 带圈数字表 (①-⑳)
local CIRCLED_NUMBERS = {
	"①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
	"⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
}

-- 跟踪 tab 创建顺序: tab_id -> 创建序号
-- 使用懒加载方式：第一次渲染时分配序号，避免 spawn-tab 事件不可靠问题
local tab_creation_order = {}
local next_tab_number = 1

-- 跟踪当前活动的 tab 索引
local last_active_tab_index = nil

-- format-tab-title 事件: 自定义 tab 标题格式 + 切换 tab 时重置输入法
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	-- 检测 tab 切换 (只在 tab 变为活动状态时触发)
	if tab.is_active and tab.tab_index ~= last_active_tab_index then
		last_active_tab_index = tab.tab_index
		-- 使用 os.execute 切换输入法 (同步执行，简单可靠)
		os.execute("/opt/homebrew/bin/im-select com.apple.keylayout.ABC &")
	end

	-- 懒分配序号：第一次遇到此 tab 时分配固定序号
	if tab.tab_id and not tab_creation_order[tab.tab_id] then
		tab_creation_order[tab.tab_id] = next_tab_number
		next_tab_number = next_tab_number + 1
	end
	local tab_number = tab_creation_order[tab.tab_id] or 1
	local symbol = CIRCLED_NUMBERS[tab_number] or ("" .. tab_number .. "")
	-- 优先使用自定义 tab 标题, 否则使用 pane 标题 (通常是当前运行的命令/程序名)
	local title = tab.tab_title ~= "" and tab.tab_title or tab.active_pane.title

	-- 安全获取当前工作目录
	local cwd = nil
	if tab.active_pane then
		cwd = tab.active_pane.current_working_dir
	end

	-- 从工作目录获取路径并匹配对应颜色
	local path = get_path_from_url(cwd)
	local color = get_color_for_path(path)

	-- 返回格式化的标题
	return {
		{ Text = " " .. symbol .. " " .. title .. " " },
	}
end)

-- ============================================================
-- UI 界面设置
-- ============================================================
-- 注意: 全屏启动需要保留窗口装饰，否则可能导致尺寸计算问题
config.window_decorations = "RESIZE" -- 保留调整大小边框，但隐藏标题栏
config.use_fancy_tab_bar = false -- 使用原生 tab bar (非 fancy)
config.show_new_tab_button_in_tab_bar = false -- 关闭新建 tab 按钮
config.hide_tab_bar_if_only_one_tab = false -- 只有一个 tab 时也显示 tab bar
config.tab_max_width = 64 -- Tab 最大宽度
config.color_scheme = "AlienBlood" -- 配色方案

-- 自定义颜色 (光标使用霓虹粉)
config.colors = {
	cursor_bg = "#ff00ff",
	cursor_fg = "#000000",
	-- Tab 栏透明效果 (使用与终端背景相同的颜色)
	tab_bar = {
		background = "#000000",
		active_tab = {
			bg_color = "#000000",
			fg_color = "#ffffff",
		},
		inactive_tab = {
			bg_color = "#000000",
			fg_color = "#888888",
		},
		inactive_tab_hover = {
			bg_color = "#222222",
			fg_color = "#ffffff",
		},
		new_tab = {
			bg_color = "#000000",
			fg_color = "#888888",
		},
		new_tab_hover = {
			bg_color = "#222222",
			fg_color = "#ffffff",
		},
	},
}
-- 注意: 全屏模式下不需要固定行列数，WezTerm 会自动适应屏幕
-- config.initial_cols = 120
-- config.initial_rows = 35
config.line_height = 1.2 -- 行高
config.cell_width = 1.07 -- 字符间距 (默认 1.0)

-- 窗口内边距
config.window_padding = {
	left = 10,
	right = 10,
	top = 0,
	bottom = 0,
}

-- 光标样式: 闪烁方块
config.default_cursor_style = "BlinkingBlock"

-- ============================================================
-- 滚动与历史记录
-- ============================================================
-- 查看历史记录时，不因新输出而自动滚动到底部
config.scroll_to_bottom_on_input = false
config.scrollback_lines = 50000 -- 保留 50000 行历史
config.enable_scroll_bar = false -- 隐藏右侧滚动条

-- ============================================================
-- 窗口透明度
-- ============================================================
config.window_background_opacity = 0.97

config.window_background_image = "/Users/john/Pictures/IMG_3762.PNG"

-- 降低背景图片亮度，让文字更清晰
config.window_background_image_hsb = {
	brightness = 0.15, -- 亮度 (0.0-1.0)，越低图片越暗
	saturation = 0.8, -- 饱和度
	hue = 1.0, -- 色调
}

return config
