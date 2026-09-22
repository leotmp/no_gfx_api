package imgui

when ODIN_OS == .Darwin {
	@(require) foreign import stdcpp "system:c++"
} else when ODIN_OS == .Linux {
    @(require) foreign import stdcpp "system:stdc++"
}

when ODIN_OS == .Windows {
	when ODIN_ARCH == .amd64 {
		foreign import lib "imgui_windows_x64.lib"
	} else {
		foreign import lib "imgui_windows_arm64.lib"
	}
} else when ODIN_OS == .Linux {
	when ODIN_ARCH == .amd64 {
		foreign import lib "libimgui_linux_x64.a"
	} else {
		foreign import lib "libimgui_linux_arm64.a"
	}
} else when ODIN_OS == .Darwin {
	when ODIN_ARCH == .amd64 {
		foreign import lib "libimgui_macosx_x64.a"
	} else {
		foreign import lib "libimgui_macosx_arm64.a"
	}
}

CHECKVERSION :: proc() {
	ensure(
		debug_check_version_and_data_layout(
			VERSION,
			size_of(IO),
			size_of(Style),
			size_of(Vec2),
			size_of(Vec4),
			size_of(Draw_Vert),
			size_of(Draw_Idx),
		),
	)
}

VERSION :: "1.91.9"
VERSION_NUM :: 19190
PAYLOAD_TYPE_COLOR_3F :: "_COL3F" // float[3]: Standard type for colors, without alpha. User code may use this type.
PAYLOAD_TYPE_COLOR_4F :: "_COL4F" // float[4]: Standard type for colors. User code may use this type.
UNICODE_CODEPOINT_INVALID :: 0xFFFD // Invalid Unicode code point (standard value).
UNICODE_CODEPOINT_MAX :: 0xFFFF // Maximum Unicode code point supported by this build.
COL32_R_SHIFT :: 0
COL32_G_SHIFT :: 8
COL32_B_SHIFT :: 16
COL32_A_SHIFT :: 24
COL32_A_MASK :: 0xFF000000
DRAWLIST_TEX_LINES_WIDTH_MAX :: 32

// Flags for ImGui::Begin()
// (Those are per-window flags. There are shared flags in ImGuiIO: io.ConfigWindowsResizeFromEdges and io.ConfigWindowsMoveFromTitleBarOnly)
Window_Flags :: bit_set[Window_Flag;i32]
Window_Flag :: enum i32 {
	No_Title_Bar                = 0, // Disable title-bar
	No_Resize                   = 1, // Disable user resizing with the lower-right grip
	No_Move                     = 2, // Disable user moving the window
	No_Scrollbar                = 3, // Disable scrollbars (window can still scroll with mouse or programmatically)
	No_Scroll_With_Mouse        = 4, // Disable user vertically scrolling with mouse wheel. On child window, mouse wheel will be forwarded to the parent unless NoScrollbar is also set.
	No_Collapse                 = 5, // Disable user collapsing window by double-clicking on it. Also referred to as Window Menu Button (e.g. within a docking node).
	Always_Auto_Resize          = 6, // Resize every window to its content every frame
	No_Background               = 7, // Disable drawing background color (WindowBg, etc.) and outside border. Similar as using SetNextWindowBgAlpha(0.0f).
	No_Saved_Settings           = 8, // Never load/save settings in .ini file
	No_Mouse_Inputs             = 9, // Disable catching mouse, hovering test with pass through.
	Menu_Bar                    = 10, // Has a menu-bar
	Horizontal_Scrollbar        = 11, // Allow horizontal scrollbar to appear (off by default). You may use SetNextWindowContentSize(ImVec2(width,0.0f)); prior to calling Begin() to specify width. Read code in imgui_demo in the "Horizontal Scrolling" section.
	No_Focus_On_Appearing       = 12, // Disable taking focus when transitioning from hidden to visible state
	No_Bring_To_Front_On_Focus  = 13, // Disable bringing window to front when taking focus (e.g. clicking on it or programmatically giving it focus)
	Always_Vertical_Scrollbar   = 14, // Always show vertical scrollbar (even if ContentSize.y < Size.y)
	Always_Horizontal_Scrollbar = 15, // Always show horizontal scrollbar (even if ContentSize.x < Size.x)
	No_Nav_Inputs               = 16, // No keyboard/gamepad navigation within the window
	No_Nav_Focus                = 17, // No focusing toward this window with keyboard/gamepad navigation (e.g. skipped by CTRL+TAB)
	Unsaved_Document            = 18, // Display a dot next to the title. When used in a tab/docking context, tab is selected when clicking the X + closure is not assumed (will wait for user to stop submitting the tab). Otherwise closure is assumed when pressing the X, so if you keep submitting the tab may reappear at end of tab bar.
	No_Docking                  = 19, // Disable docking of this window
}

WINDOW_FLAGS_NO_NAV :: Window_Flags{.No_Nav_Inputs, .No_Nav_Focus}
WINDOW_FLAGS_NO_DECORATION :: Window_Flags{.No_Title_Bar, .No_Resize, .No_Scrollbar, .No_Collapse}
WINDOW_FLAGS_NO_INPUTS :: Window_Flags{.No_Mouse_Inputs, .No_Nav_Inputs, .No_Nav_Focus}

// Flags for ImGui::BeginChild()
// (Legacy: bit 0 must always correspond to ImGuiChildFlags_Borders to be backward compatible with old API using 'bool border = false'.
// About using AutoResizeX/AutoResizeY flags:
// - May be combined with SetNextWindowSizeConstraints() to set a min/max size for each axis (see "Demo->Child->Auto-resize with Constraints").
// - Size measurement for a given axis is only performed when the child window is within visible boundaries, or is just appearing.
//   - This allows BeginChild() to return false when not within boundaries (e.g. when scrolling), which is more optimal. BUT it won't update its auto-size while clipped.
//     While not perfect, it is a better default behavior as the always-on performance gain is more valuable than the occasional "resizing after becoming visible again" glitch.
//   - You may also use ImGuiChildFlags_AlwaysAutoResize to force an update even when child window is not in view.
//     HOWEVER PLEASE UNDERSTAND THAT DOING SO WILL PREVENT BeginChild() FROM EVER RETURNING FALSE, disabling benefits of coarse clipping.
Child_Flags :: bit_set[Child_Flag;i32]
Child_Flag :: enum i32 {
	Borders                   = 0, // Show an outer border and enable WindowPadding. (IMPORTANT: this is always == 1 == true for legacy reason)
	Always_Use_Window_Padding = 1, // Pad with style.WindowPadding even if no border are drawn (no padding by default for non-bordered child windows because it makes more sense)
	Resize_X                  = 2, // Allow resize from right border (layout direction). Enable .ini saving (unless ImGuiWindowFlags_NoSavedSettings passed to window flags)
	Resize_Y                  = 3, // Allow resize from bottom border (layout direction). "
	Auto_Resize_X             = 4, // Enable auto-resizing width. Read "IMPORTANT: Size measurement" details above.
	Auto_Resize_Y             = 5, // Enable auto-resizing height. Read "IMPORTANT: Size measurement" details above.
	Always_Auto_Resize        = 6, // Combined with AutoResizeX/AutoResizeY. Always measure size even when child is hidden, always return true, always disable clipping optimization! NOT RECOMMENDED.
	Frame_Style               = 7, // Style the child window like a framed item: use FrameBg, FrameRounding, FrameBorderSize, FramePadding instead of ChildBg, ChildRounding, ChildBorderSize, WindowPadding.
	Nav_Flattened             = 8, // [BETA] Share focus scope, allow keyboard/gamepad navigation to cross over parent border to this child or between sibling child windows.
}

// Flags for ImGui::PushItemFlag()
// (Those are shared by all items)
Item_Flags :: bit_set[Item_Flag;i32]
Item_Flag :: enum i32 {
	No_Tab_Stop          = 0, // false    // Disable keyboard tabbing. This is a "lighter" version of ImGuiItemFlags_NoNav.
	No_Nav               = 1, // false    // Disable any form of focusing (keyboard/gamepad directional navigation and SetKeyboardFocusHere() calls).
	No_Nav_Default_Focus = 2, // false    // Disable item being a candidate for default focus (e.g. used by title bar items).
	Button_Repeat        = 3, // false    // Any button-like behavior will have repeat mode enabled (based on io.KeyRepeatDelay and io.KeyRepeatRate values). Note that you can also call IsItemActive() after any button to tell if it is being held.
	Auto_Close_Popups    = 4, // true     // MenuItem()/Selectable() automatically close their parent popup window.
	Allow_Duplicate_Id   = 5, // false    // Allow submitting an item with the same identifier as an item already submitted this frame without triggering a warning tooltip if io.ConfigDebugHighlightIdConflicts is set.
}

// Flags for ImGui::InputText()
// (Those are per-item flags. There are shared flags in ImGuiIO: io.ConfigInputTextCursorBlink and io.ConfigInputTextEnterKeepActive)
Input_Text_Flags :: bit_set[Input_Text_Flag;i32]
Input_Text_Flag :: enum i32 {
	Chars_Decimal           = 0, // Allow 0123456789.+-*/
	Chars_Hexadecimal       = 1, // Allow 0123456789ABCDEFabcdef
	Chars_Scientific        = 2, // Allow 0123456789.+-*/eE (Scientific notation input)
	Chars_Uppercase         = 3, // Turn a..z into A..Z
	Chars_No_Blank          = 4, // Filter out spaces, tabs
	Allow_Tab_Input         = 5, // Pressing TAB input a '\t' character into the text field
	Enter_Returns_True      = 6, // Return 'true' when Enter is pressed (as opposed to every time the value was modified). Consider using IsItemDeactivatedAfterEdit() instead!
	Escape_Clears_All       = 7, // Escape key clears content if not empty, and deactivate otherwise (contrast to default behavior of Escape to revert)
	Ctrl_Enter_For_New_Line = 8, // In multi-line mode, validate with Enter, add new line with Ctrl+Enter (default is opposite: validate with Ctrl+Enter, add line with Enter).
	Read_Only               = 9, // Read-only mode
	Password                = 10, // Password mode, display all characters as '*', disable copy
	Always_Overwrite        = 11, // Overwrite mode
	Auto_Select_All         = 12, // Select entire text when first taking mouse focus
	Parse_Empty_Ref_Val     = 13, // InputFloat(), InputInt(), InputScalar() etc. only: parse empty string as zero value.
	Display_Empty_Ref_Val   = 14, // InputFloat(), InputInt(), InputScalar() etc. only: when value is zero, do not display it. Generally used with ImGuiInputTextFlags_ParseEmptyRefVal.
	No_Horizontal_Scroll    = 15, // Disable following the cursor horizontally
	No_Undo_Redo            = 16, // Disable undo/redo. Note that input text owns the text data while active, if you want to provide your own undo/redo stack you need e.g. to call ClearActiveID().
	Elide_Left              = 17, // When text doesn't fit, elide left side to ensure right side stays visible. Useful for path/filenames. Single-line only!
	Callback_Completion     = 18, // Callback on pressing TAB (for completion handling)
	Callback_History        = 19, // Callback on pressing Up/Down arrows (for history handling)
	Callback_Always         = 20, // Callback on each iteration. User code may query cursor position, modify text buffer.
	Callback_Char_Filter    = 21, // Callback on character inputs to replace or discard them. Modify 'EventChar' to replace or discard, or return 1 in callback to discard.
	Callback_Resize         = 22, // Callback on buffer capacity changes request (beyond 'buf_size' parameter value), allowing the string to grow. Notify when the string wants to be resized (for string types which hold a cache of their Size). You will be provided a new BufSize in the callback and NEED to honor it. (see misc/cpp/imgui_stdlib.h for an example of using this)
	Callback_Edit           = 23, // Callback on any edit. Note that InputText() already returns true on edit + you can always use IsItemEdited(). The callback is useful to manipulate the underlying buffer while focus is active.
}

// Flags for ImGui::TreeNodeEx(), ImGui::CollapsingHeader*()
Tree_Node_Flags :: bit_set[Tree_Node_Flag;i32]
Tree_Node_Flag :: enum i32 {
	Selected                 = 0, // Draw as selected
	Framed                   = 1, // Draw frame with background (e.g. for CollapsingHeader)
	Allow_Overlap            = 2, // Hit testing to allow subsequent widgets to overlap this one
	No_Tree_Push_On_Open     = 3, // Don't do a TreePush() when open (e.g. for CollapsingHeader) = no extra indent nor pushing on ID stack
	No_Auto_Open_On_Log      = 4, // Don't automatically and temporarily open node when Logging is active (by default logging will automatically open tree nodes)
	Default_Open             = 5, // Default node to be open
	Open_On_Double_Click     = 6, // Open on double-click instead of simple click (default for multi-select unless any _OpenOnXXX behavior is set explicitly). Both behaviors may be combined.
	Open_On_Arrow            = 7, // Open when clicking on the arrow part (default for multi-select unless any _OpenOnXXX behavior is set explicitly). Both behaviors may be combined.
	Leaf                     = 8, // No collapsing, no arrow (use as a convenience for leaf nodes).
	Bullet                   = 9, // Display a bullet instead of arrow. IMPORTANT: node can still be marked open/close if you don't set the _Leaf flag!
	Frame_Padding            = 10, // Use FramePadding (even for an unframed text node) to vertically align text baseline to regular widget height. Equivalent to calling AlignTextToFramePadding() before the node.
	Span_Avail_Width         = 11, // Extend hit box to the right-most edge, even if not framed. This is not the default in order to allow adding other items on the same line without using AllowOverlap mode.
	Span_Full_Width          = 12, // Extend hit box to the left-most and right-most edges (cover the indent area).
	Span_Label_Width         = 13, // Narrow hit box + narrow hovering highlight, will only cover the label text.
	Span_All_Columns         = 14, // Frame will span all columns of its container table (label will still fit in current column)
	Label_Span_All_Columns   = 15, // Label will span all columns of its container table
	Nav_Left_Jumps_Back_Here = 17, // (WIP) Nav: left direction may move to this TreeNode() from any of its child (items submitted between TreeNode and TreePop)
}

TREE_NODE_FLAGS_COLLAPSING_HEADER :: Tree_Node_Flags {
	.Framed,
	.No_Tree_Push_On_Open,
	.No_Auto_Open_On_Log,
}

// Flags for OpenPopup*(), BeginPopupContext*(), IsPopupOpen() functions.
// - To be backward compatible with older API which took an 'int mouse_button = 1' argument instead of 'ImGuiPopupFlags flags',
//   we need to treat small flags values as a mouse button index, so we encode the mouse button in the first few bits of the flags.
//   It is therefore guaranteed to be legal to pass a mouse button index in ImGuiPopupFlags.
// - For the same reason, we exceptionally default the ImGuiPopupFlags argument of BeginPopupContextXXX functions to 1 instead of 0.
//   IMPORTANT: because the default parameter is 1 (==ImGuiPopupFlags_MouseButtonRight), if you rely on the default parameter
//   and want to use another flag, you need to pass in the ImGuiPopupFlags_MouseButtonRight flag explicitly.
// - Multiple buttons currently cannot be combined/or-ed in those functions (we could allow it later).
Popup_Flags :: bit_set[Popup_Flag;i32]
Popup_Flag :: enum i32 {
	Mouse_Button_Left           = 0, // For BeginPopupContext*(): open on Left Mouse release. Guaranteed to always be == 0 (same as ImGuiMouseButton_Left)
	Mouse_Button_Right          = 1, // For BeginPopupContext*(): open on Right Mouse release. Guaranteed to always be == 1 (same as ImGuiMouseButton_Right)
	Mouse_Button_Middle         = 2, // For BeginPopupContext*(): open on Middle Mouse release. Guaranteed to always be == 2 (same as ImGuiMouseButton_Middle)
	No_Reopen                   = 5, // For OpenPopup*(), BeginPopupContext*(): don't reopen same popup if already open (won't reposition, won't reinitialize navigation)
	No_Open_Over_Existing_Popup = 7, // For OpenPopup*(), BeginPopupContext*(): don't open if there's already a popup at the same level of the popup stack
	No_Open_Over_Items          = 8, // For BeginPopupContextWindow(): don't return true when hovering items, only when hovering empty space
	Any_Popup_Id                = 10, // For IsPopupOpen(): ignore the ImGuiID parameter and test for any popup.
	Any_Popup_Level             = 11, // For IsPopupOpen(): search/test at any level of the popup stack (default test in the current level)
}

POPUP_FLAGS_ANY_POPUP :: Popup_Flags{.Any_Popup_Id, .Any_Popup_Level}

// Flags for ImGui::Selectable()
Selectable_Flags :: bit_set[Selectable_Flag;i32]
Selectable_Flag :: enum i32 {
	No_Auto_Close_Popups = 0, // Clicking this doesn't close parent popup window (overrides ImGuiItemFlags_AutoClosePopups)
	Span_All_Columns     = 1, // Frame will span all columns of its container table (text will still fit in current column)
	Allow_Double_Click   = 2, // Generate press events on double clicks too
	Disabled             = 3, // Cannot be selected, display grayed out text
	Allow_Overlap        = 4, // (WIP) Hit testing to allow subsequent widgets to overlap this one
	Highlight            = 5, // Make the item be displayed as if it is hovered
}

// Flags for ImGui::BeginCombo()
Combo_Flags :: bit_set[Combo_Flag;i32]
Combo_Flag :: enum i32 {
	Popup_Align_Left  = 0, // Align the popup toward the left by default
	Height_Small      = 1, // Max ~4 items visible. Tip: If you want your combo popup to be a specific size you can use SetNextWindowSizeConstraints() prior to calling BeginCombo()
	Height_Regular    = 2, // Max ~8 items visible (default)
	Height_Large      = 3, // Max ~20 items visible
	Height_Largest    = 4, // As many fitting items as possible
	No_Arrow_Button   = 5, // Display on the preview box without the square arrow button
	No_Preview        = 6, // Display only a square arrow button
	Width_Fit_Preview = 7, // Width dynamically calculated from preview contents
}

// Flags for ImGui::BeginTabBar()
Tab_Bar_Flags :: bit_set[Tab_Bar_Flag;i32]
Tab_Bar_Flag :: enum i32 {
	Reorderable                       = 0, // Allow manually dragging tabs to re-order them + New tabs are appended at the end of list
	Auto_Select_New_Tabs              = 1, // Automatically select new tabs when they appear
	Tab_List_Popup_Button             = 2, // Disable buttons to open the tab list popup
	No_Close_With_Middle_Mouse_Button = 3, // Disable behavior of closing tabs (that are submitted with p_open != NULL) with middle mouse button. You may handle this behavior manually on user's side with if (IsItemHovered() && IsMouseClicked(2)) *p_open = false.
	No_Tab_List_Scrolling_Buttons     = 4, // Disable scrolling buttons (apply when fitting policy is ImGuiTabBarFlags_FittingPolicyScroll)
	No_Tooltip                        = 5, // Disable tooltips when hovering a tab
	Draw_Selected_Overline            = 6, // Draw selected overline markers over selected tab
	Fitting_Policy_Resize_Down        = 7, // Resize tabs when they don't fit
	Fitting_Policy_Scroll             = 8, // Add scroll buttons when tabs don't fit
}

// Flags for ImGui::BeginTabItem()
Tab_Item_Flags :: bit_set[Tab_Item_Flag;i32]
Tab_Item_Flag :: enum i32 {
	Unsaved_Document                  = 0, // Display a dot next to the title + set ImGuiTabItemFlags_NoAssumedClosure.
	Set_Selected                      = 1, // Trigger flag to programmatically make the tab selected when calling BeginTabItem()
	No_Close_With_Middle_Mouse_Button = 2, // Disable behavior of closing tabs (that are submitted with p_open != NULL) with middle mouse button. You may handle this behavior manually on user's side with if (IsItemHovered() && IsMouseClicked(2)) *p_open = false.
	No_Push_Id                        = 3, // Don't call PushID()/PopID() on BeginTabItem()/EndTabItem()
	No_Tooltip                        = 4, // Disable tooltip for the given tab
	No_Reorder                        = 5, // Disable reordering this tab or having another tab cross over this tab
	Leading                           = 6, // Enforce the tab position to the left of the tab bar (after the tab list popup button)
	Trailing                          = 7, // Enforce the tab position to the right of the tab bar (before the scrolling buttons)
	No_Assumed_Closure                = 8, // Tab is selected when trying to close + closure is not immediately assumed (will wait for user to stop submitting the tab). Otherwise closure is assumed when pressing the X, so if you keep submitting the tab may reappear at end of tab bar.
}

// Flags for ImGui::IsWindowFocused()
Focused_Flags :: bit_set[Focused_Flag;i32]
Focused_Flag :: enum i32 {
	Child_Windows      = 0, // Return true if any children of the window is focused
	Root_Window        = 1, // Test from root window (top most parent of the current hierarchy)
	Any_Window         = 2, // Return true if any window is focused. Important: If you are trying to tell how to dispatch your low-level inputs, do NOT use this. Use 'io.WantCaptureMouse' instead! Please read the FAQ!
	No_Popup_Hierarchy = 3, // Do not consider popup hierarchy (do not treat popup emitter as parent of popup) (when used with _ChildWindows or _RootWindow)
	Dock_Hierarchy     = 4, // Consider docking hierarchy (treat dockspace host as parent of docked window) (when used with _ChildWindows or _RootWindow)
}

FOCUSED_FLAGS_ROOT_AND_CHILD_WINDOWS :: Focused_Flags{.Root_Window, .Child_Windows}

// Flags for ImGui::IsItemHovered(), ImGui::IsWindowHovered()
// Note: if you are trying to check whether your mouse should be dispatched to Dear ImGui or to your app, you should use 'io.WantCaptureMouse' instead! Please read the FAQ!
// Note: windows with the ImGuiWindowFlags_NoInputs flag are ignored by IsWindowHovered() calls.
Hovered_Flags :: bit_set[Hovered_Flag;i32]
Hovered_Flag :: enum i32 {
	Child_Windows                     = 0, // IsWindowHovered() only: Return true if any children of the window is hovered
	Root_Window                       = 1, // IsWindowHovered() only: Test from root window (top most parent of the current hierarchy)
	Any_Window                        = 2, // IsWindowHovered() only: Return true if any window is hovered
	No_Popup_Hierarchy                = 3, // IsWindowHovered() only: Do not consider popup hierarchy (do not treat popup emitter as parent of popup) (when used with _ChildWindows or _RootWindow)
	Dock_Hierarchy                    = 4, // IsWindowHovered() only: Consider docking hierarchy (treat dockspace host as parent of docked window) (when used with _ChildWindows or _RootWindow)
	Allow_When_Blocked_By_Popup       = 5, // Return true even if a popup window is normally blocking access to this item/window
	Allow_When_Blocked_By_Active_Item = 7, // Return true even if an active item is blocking access to this item/window. Useful for Drag and Drop patterns.
	Allow_When_Overlapped_By_Item     = 8, // IsItemHovered() only: Return true even if the item uses AllowOverlap mode and is overlapped by another hoverable item.
	Allow_When_Overlapped_By_Window   = 9, // IsItemHovered() only: Return true even if the position is obstructed or overlapped by another window.
	Allow_When_Disabled               = 10, // IsItemHovered() only: Return true even if the item is disabled
	No_Nav_Override                   = 11, // IsItemHovered() only: Disable using keyboard/gamepad navigation state when active, always query mouse
	For_Tooltip                       = 12, // Shortcut for standard flags when using IsItemHovered() + SetTooltip() sequence.
	Stationary                        = 13, // Require mouse to be stationary for style.HoverStationaryDelay (~0.15 sec) _at least one time_. After this, can move on same item/window. Using the stationary test tends to reduces the need for a long delay.
	Delay_None                        = 14, // IsItemHovered() only: Return true immediately (default). As this is the default you generally ignore this.
	Delay_Short                       = 15, // IsItemHovered() only: Return true after style.HoverDelayShort elapsed (~0.15 sec) (shared between items) + requires mouse to be stationary for style.HoverStationaryDelay (once per item).
	Delay_Normal                      = 16, // IsItemHovered() only: Return true after style.HoverDelayNormal elapsed (~0.40 sec) (shared between items) + requires mouse to be stationary for style.HoverStationaryDelay (once per item).
	No_Shared_Delay                   = 17, // IsItemHovered() only: Disable shared delay system where moving from one item to the next keeps the previous timer for a short time (standard for tooltips with long delays)
}

HOVERED_FLAGS_ALLOW_WHEN_OVERLAPPED :: Hovered_Flags {
	.Allow_When_Overlapped_By_Item,
	.Allow_When_Overlapped_By_Window,
}
HOVERED_FLAGS_RECT_ONLY :: Hovered_Flags {
	.Allow_When_Blocked_By_Popup,
	.Allow_When_Blocked_By_Active_Item,
	.Allow_When_Overlapped_By_Item,
	.Allow_When_Overlapped_By_Window,
}
HOVERED_FLAGS_ROOT_AND_CHILD_WINDOWS :: Hovered_Flags{.Root_Window, .Child_Windows}

// Flags for ImGui::DockSpace(), shared/inherited by child nodes.
// (Some flags can be applied to individual nodes directly)
// FIXME-DOCK: Also see ImGuiDockNodeFlagsPrivate_ which may involve using the WIP and internal DockBuilder api.
Dock_Node_Flags :: bit_set[Dock_Node_Flag;i32]
Dock_Node_Flag :: enum i32 {
	Keep_Alive_Only              = 0, //       // Don't display the dockspace node but keep it alive. Windows docked into this dockspace node won't be undocked.
	No_Docking_Over_Central_Node = 2, //       // Disable docking over the Central Node, which will be always kept empty.
	Passthru_Central_Node        = 3, //       // Enable passthru dockspace: 1) DockSpace() will render a ImGuiCol_WindowBg background covering everything excepted the Central Node when empty. Meaning the host window should probably use SetNextWindowBgAlpha(0.0f) prior to Begin() when using this. 2) When Central Node is empty: let inputs pass-through + won't display a DockingEmptyBg background. See demo for details.
	No_Docking_Split             = 4, //       // Disable other windows/nodes from splitting this node.
	No_Resize                    = 5, // Saved // Disable resizing node using the splitter/separators. Useful with programmatically setup dockspaces.
	Auto_Hide_Tab_Bar            = 6, //       // Tab bar will automatically hide when there is a single window in the dock node.
	No_Undocking                 = 7, //       // Disable undocking this node.
}

// Flags for ImGui::BeginDragDropSource(), ImGui::AcceptDragDropPayload()
Drag_Drop_Flags :: bit_set[Drag_Drop_Flag;i32]
Drag_Drop_Flag :: enum i32 {
	Source_No_Preview_Tooltip     = 0, // Disable preview tooltip. By default, a successful call to BeginDragDropSource opens a tooltip so you can display a preview or description of the source contents. This flag disables this behavior.
	Source_No_Disable_Hover       = 1, // By default, when dragging we clear data so that IsItemHovered() will return false, to avoid subsequent user code submitting tooltips. This flag disables this behavior so you can still call IsItemHovered() on the source item.
	Source_No_Hold_To_Open_Others = 2, // Disable the behavior that allows to open tree nodes and collapsing header by holding over them while dragging a source item.
	Source_Allow_Null_ID          = 3, // Allow items such as Text(), Image() that have no unique identifier to be used as drag source, by manufacturing a temporary identifier based on their window-relative position. This is extremely unusual within the dear imgui ecosystem and so we made it explicit.
	Source_Extern                 = 4, // External source (from outside of dear imgui), won't attempt to read current item/window info. Will always return true. Only one Extern source can be active simultaneously.
	Payload_Auto_Expire           = 5, // Automatically expire the payload if the source cease to be submitted (otherwise payloads are persisting while being dragged)
	Payload_No_Cross_Context      = 6, // Hint to specify that the payload may not be copied outside current dear imgui context.
	Payload_No_Cross_Process      = 7, // Hint to specify that the payload may not be copied outside current process.
	Accept_Before_Delivery        = 10, // AcceptDragDropPayload() will returns true even before the mouse button is released. You can then call IsDelivery() to test if the payload needs to be delivered.
	Accept_No_Draw_Default_Rect   = 11, // Do not draw the default highlight rectangle when hovering over target.
	Accept_No_Preview_Tooltip     = 12, // Request hiding the BeginDragDropSource tooltip from the BeginDragDropTarget site.
}

DRAG_DROP_FLAGS_ACCEPT_PEEK_ONLY :: Drag_Drop_Flags {
	.Accept_Before_Delivery,
	.Accept_No_Draw_Default_Rect,
}

// A primary data type
Data_Type :: enum i32 {
	S8     = 0, // signed char / char (with sensible compilers)
	U8     = 1, // unsigned char
	S16    = 2, // short
	U16    = 3, // unsigned short
	S32    = 4, // int
	U32    = 5, // unsigned int
	S64    = 6, // long long / __int64
	U64    = 7, // unsigned long long / unsigned __int64
	Float  = 8, // float
	Double = 9, // double
	Bool   = 10, // bool (provided for user convenience, not supported by scalar widgets)
	String = 11, // char* (provided for user convenience, not supported by scalar widgets)
}

DATA_TYPE_COUNT :: 12

// A cardinal direction
Dir :: enum i32 {
	None  = -1,
	Left  = 0,
	Right = 1,
	Up    = 2,
	Down  = 3,
}

DIR_COUNT :: 4

// A sorting direction
Sort_Direction :: enum i32 {
	None       = 0,
	Ascending  = 1, // Ascending = 0->9, A->Z etc.
	Descending = 2, // Descending = 9->0, Z->A etc.
}

// A key identifier (ImGuiKey_XXX or ImGuiMod_XXX value): can represent Keyboard, Mouse and Gamepad values.
// All our named keys are >= 512. Keys value 0 to 511 are left unused and were legacy native/opaque key values (< 1.87).
// Support for legacy keys was completely removed in 1.91.5.
// Read details about the 1.87+ transition : https://github.com/ocornut/imgui/issues/4921
// Note that "Keys" related to physical keys and are not the same concept as input "Characters", the later are submitted via io.AddInputCharacter().
// The keyboard key enum values are named after the keys on a standard US keyboard, and on other keyboard types the keys reported may not match the keycaps.
Key :: enum i32 {
	None                   = 0,
	Tab                    = 512, // == ImGuiKey_NamedKey_BEGIN
	Left_Arrow             = 513,
	Right_Arrow            = 514,
	Up_Arrow               = 515,
	Down_Arrow             = 516,
	Page_Up                = 517,
	Page_Down              = 518,
	Home                   = 519,
	End                    = 520,
	Insert                 = 521,
	Delete                 = 522,
	Backspace              = 523,
	Space                  = 524,
	Enter                  = 525,
	Escape                 = 526,
	Left_Ctrl              = 527,
	Left_Shift             = 528,
	Left_Alt               = 529,
	Left_Super             = 530,
	Right_Ctrl             = 531,
	Right_Shift            = 532,
	Right_Alt              = 533,
	Right_Super            = 534,
	Menu                   = 535,
	_0                     = 536,
	_1                     = 537,
	_2                     = 538,
	_3                     = 539,
	_4                     = 540,
	_5                     = 541,
	_6                     = 542,
	_7                     = 543,
	_8                     = 544,
	_9                     = 545,
	A                      = 546,
	B                      = 547,
	C                      = 548,
	D                      = 549,
	E                      = 550,
	F                      = 551,
	G                      = 552,
	H                      = 553,
	I                      = 554,
	J                      = 555,
	K                      = 556,
	L                      = 557,
	M                      = 558,
	N                      = 559,
	O                      = 560,
	P                      = 561,
	Q                      = 562,
	R                      = 563,
	S                      = 564,
	T                      = 565,
	U                      = 566,
	V                      = 567,
	W                      = 568,
	X                      = 569,
	Y                      = 570,
	Z                      = 571,
	F1                     = 572,
	F2                     = 573,
	F3                     = 574,
	F4                     = 575,
	F5                     = 576,
	F6                     = 577,
	F7                     = 578,
	F8                     = 579,
	F9                     = 580,
	F10                    = 581,
	F11                    = 582,
	F12                    = 583,
	F13                    = 584,
	F14                    = 585,
	F15                    = 586,
	F16                    = 587,
	F17                    = 588,
	F18                    = 589,
	F19                    = 590,
	F20                    = 591,
	F21                    = 592,
	F22                    = 593,
	F23                    = 594,
	F24                    = 595,
	Apostrophe             = 596, // '
	Comma                  = 597, // ,
	Minus                  = 598, // -
	Period                 = 599, // .
	Slash                  = 600, // /
	Semicolon              = 601, // ;
	Equal                  = 602, // =
	Left_Bracket           = 603, // [
	Backslash              = 604, // \ (this text inhibit multiline comment caused by backslash)
	Right_Bracket          = 605, // ]
	Grave_Accent           = 606, // `
	Caps_Lock              = 607,
	Scroll_Lock            = 608,
	Num_Lock               = 609,
	Print_Screen           = 610,
	Pause                  = 611,
	Keypad0                = 612,
	Keypad1                = 613,
	Keypad2                = 614,
	Keypad3                = 615,
	Keypad4                = 616,
	Keypad5                = 617,
	Keypad6                = 618,
	Keypad7                = 619,
	Keypad8                = 620,
	Keypad9                = 621,
	Keypad_Decimal         = 622,
	Keypad_Divide          = 623,
	Keypad_Multiply        = 624,
	Keypad_Subtract        = 625,
	Keypad_Add             = 626,
	Keypad_Enter           = 627,
	Keypad_Equal           = 628,
	App_Back               = 629, // Available on some keyboard/mouses. Often referred as "Browser Back"
	App_Forward            = 630,
	Oem102                 = 631, // Non-US backslash.
	Gamepad_Start          = 632, // Menu (Xbox)      + (Switch)   Start/Options (PS)
	Gamepad_Back           = 633, // View (Xbox)      - (Switch)   Share (PS)
	Gamepad_Face_Left      = 634, // X (Xbox)         Y (Switch)   Square (PS)        // Tap: Toggle Menu. Hold: Windowing mode (Focus/Move/Resize windows)
	Gamepad_Face_Right     = 635, // B (Xbox)         A (Switch)   Circle (PS)        // Cancel / Close / Exit
	Gamepad_Face_Up        = 636, // Y (Xbox)         X (Switch)   Triangle (PS)      // Text Input / On-screen Keyboard
	Gamepad_Face_Down      = 637, // A (Xbox)         B (Switch)   Cross (PS)         // Activate / Open / Toggle / Tweak
	Gamepad_Dpad_Left      = 638, // D-pad Left                                       // Move / Tweak / Resize Window (in Windowing mode)
	Gamepad_Dpad_Right     = 639, // D-pad Right                                      // Move / Tweak / Resize Window (in Windowing mode)
	Gamepad_Dpad_Up        = 640, // D-pad Up                                         // Move / Tweak / Resize Window (in Windowing mode)
	Gamepad_Dpad_Down      = 641, // D-pad Down                                       // Move / Tweak / Resize Window (in Windowing mode)
	Gamepad_L1             = 642, // L Bumper (Xbox)  L (Switch)   L1 (PS)            // Tweak Slower / Focus Previous (in Windowing mode)
	Gamepad_R1             = 643, // R Bumper (Xbox)  R (Switch)   R1 (PS)            // Tweak Faster / Focus Next (in Windowing mode)
	Gamepad_L2             = 644, // L Trig. (Xbox)   ZL (Switch)  L2 (PS) [Analog]
	Gamepad_R2             = 645, // R Trig. (Xbox)   ZR (Switch)  R2 (PS) [Analog]
	Gamepad_L3             = 646, // L Stick (Xbox)   L3 (Switch)  L3 (PS)
	Gamepad_R3             = 647, // R Stick (Xbox)   R3 (Switch)  R3 (PS)
	Gamepad_L_Stick_Left   = 648, // [Analog]                                         // Move Window (in Windowing mode)
	Gamepad_L_Stick_Right  = 649, // [Analog]                                         // Move Window (in Windowing mode)
	Gamepad_L_Stick_Up     = 650, // [Analog]                                         // Move Window (in Windowing mode)
	Gamepad_L_Stick_Down   = 651, // [Analog]                                         // Move Window (in Windowing mode)
	Gamepad_R_Stick_Left   = 652, // [Analog]
	Gamepad_R_Stick_Right  = 653, // [Analog]
	Gamepad_R_Stick_Up     = 654, // [Analog]
	Gamepad_R_Stick_Down   = 655, // [Analog]
	Mouse_Left             = 656,
	Mouse_Right            = 657,
	Mouse_Middle           = 658,
	Mouse_X1               = 659,
	Mouse_X2               = 660,
	Mouse_Wheel_X          = 661,
	Mouse_Wheel_Y          = 662,
	Reserved_For_Mod_Ctrl  = 663,
	Reserved_For_Mod_Shift = 664,
	Reserved_For_Mod_Alt   = 665,
	Reserved_For_Mod_Super = 666,
}

KEY_NAMED_KEY_BEGIN :: 512
KEY_NAMED_KEY_END :: 667
KEY_NAMED_KEY_COUNT :: 155
KEY_MOD_NONE :: 0
KEY_MOD_CTRL :: 4096
KEY_MOD_SHIFT :: 8192
KEY_MOD_ALT :: 16384
KEY_MOD_SUPER :: 32768
KEY_MOD_MASK :: 61440

// Flags for Shortcut(), SetNextItemShortcut(),
// (and for upcoming extended versions of IsKeyPressed(), IsMouseClicked(), Shortcut(), SetKeyOwner(), SetItemKeyOwner() that are still in imgui_internal.h)
// Don't mistake with ImGuiInputTextFlags! (which is for ImGui::InputText() function)
Input_Flags :: bit_set[Input_Flag;i32]
Input_Flag :: enum i32 {
	Repeat                  = 0, // Enable repeat. Return true on successive repeats. Default for legacy IsKeyPressed(). NOT Default for legacy IsMouseClicked(). MUST BE == 1.
	Route_Active            = 10, // Route to active item only.
	Route_Focused           = 11, // Route to windows in the focus stack (DEFAULT). Deep-most focused window takes inputs. Active item takes inputs over deep-most focused window.
	Route_Global            = 12, // Global route (unless a focused window or active item registered the route).
	Route_Always            = 13, // Do not register route, poll keys directly.
	Route_Over_Focused      = 14, // Option: global route: higher priority than focused route (unless active item in focused route).
	Route_Over_Active       = 15, // Option: global route: higher priority than active item. Unlikely you need to use that: will interfere with every active items, e.g. CTRL+A registered by InputText will be overridden by this. May not be fully honored as user/internal code is likely to always assume they can access keys when active.
	Route_Unless_Bg_Focused = 16, // Option: global route: will not be applied if underlying background/void is focused (== no Dear ImGui windows are focused). Useful for overlay applications.
	Route_From_Root_Window  = 17, // Option: route evaluated from the point of view of root window rather than current window.
	Tooltip                 = 18, // Automatically display a tooltip when hovering item [BETA] Unsure of right api (opt-in/opt-out)
}

// Configuration flags stored in io.ConfigFlags. Set by user/application.
Config_Flags :: bit_set[Config_Flag;i32]
Config_Flag :: enum i32 {
	Nav_Enable_Keyboard        = 0, // Master keyboard navigation enable flag. Enable full Tabbing + directional arrows + space/enter to activate.
	Nav_Enable_Gamepad         = 1, // Master gamepad navigation enable flag. Backend also needs to set ImGuiBackendFlags_HasGamepad.
	No_Mouse                   = 4, // Instruct dear imgui to disable mouse inputs and interactions.
	No_Mouse_Cursor_Change     = 5, // Instruct backend to not alter mouse cursor shape and visibility. Use if the backend cursor changes are interfering with yours and you don't want to use SetMouseCursor() to change mouse cursor. You may want to honor requests from imgui by reading GetMouseCursor() yourself instead.
	No_Keyboard                = 6, // Instruct dear imgui to disable keyboard inputs and interactions. This is done by ignoring keyboard events and clearing existing states.
	Docking_Enable             = 7, // Docking enable flags.
	Viewports_Enable           = 10, // Viewport enable flags (require both ImGuiBackendFlags_PlatformHasViewports + ImGuiBackendFlags_RendererHasViewports set by the respective backends)
	Dpi_Enable_Scale_Viewports = 14, // [BETA: Don't use] FIXME-DPI: Reposition and resize imgui windows when the DpiScale of a viewport changed (mostly useful for the main viewport hosting other window). Note that resizing the main window itself is up to your application.
	Dpi_Enable_Scale_Fonts     = 15, // [BETA: Don't use] FIXME-DPI: Request bitmap-scaled fonts to match DpiScale. This is a very low-quality workaround. The correct way to handle DPI is _currently_ to replace the atlas and/or fonts in the Platform_OnChangedViewport callback, but this is all early work in progress.
	Is_SRGB                    = 20, // Application is SRGB-aware.
	Is_Touch_Screen            = 21, // Application is using a touch screen instead of a mouse.
}

// Backend capabilities flags stored in io.BackendFlags. Set by imgui_impl_xxx or custom backend.
Backend_Flags :: bit_set[Backend_Flag;i32]
Backend_Flag :: enum i32 {
	Has_Gamepad                = 0, // Backend Platform supports gamepad and currently has one connected.
	Has_Mouse_Cursors          = 1, // Backend Platform supports honoring GetMouseCursor() value to change the OS cursor shape.
	Has_Set_Mouse_Pos          = 2, // Backend Platform supports io.WantSetMousePos requests to reposition the OS mouse position (only used if io.ConfigNavMoveSetMousePos is set).
	Renderer_Has_Vtx_Offset    = 3, // Backend Renderer supports ImDrawCmd::VtxOffset. This enables output of large meshes (64K+ vertices) while still using 16-bit indices.
	Platform_Has_Viewports     = 10, // Backend Platform supports multiple viewports.
	Has_Mouse_Hovered_Viewport = 11, // Backend Platform supports calling io.AddMouseViewportEvent() with the viewport under the mouse. IF POSSIBLE, ignore viewports with the ImGuiViewportFlags_NoInputs flag (Win32 backend, GLFW 3.30+ backend can do this, SDL backend cannot). If this cannot be done, Dear ImGui needs to use a flawed heuristic to find the viewport under.
	Renderer_Has_Viewports     = 12, // Backend Renderer supports multiple viewports.
}

// Enumeration for PushStyleColor() / PopStyleColor()
Col :: enum i32 {
	Text                         = 0,
	Text_Disabled                = 1,
	Window_Bg                    = 2, // Background of normal windows
	Child_Bg                     = 3, // Background of child windows
	Popup_Bg                     = 4, // Background of popups, menus, tooltips windows
	Border                       = 5,
	Border_Shadow                = 6,
	Frame_Bg                     = 7, // Background of checkbox, radio button, plot, slider, text input
	Frame_Bg_Hovered             = 8,
	Frame_Bg_Active              = 9,
	Title_Bg                     = 10, // Title bar
	Title_Bg_Active              = 11, // Title bar when focused
	Title_Bg_Collapsed           = 12, // Title bar when collapsed
	Menu_Bar_Bg                  = 13,
	Scrollbar_Bg                 = 14,
	Scrollbar_Grab               = 15,
	Scrollbar_Grab_Hovered       = 16,
	Scrollbar_Grab_Active        = 17,
	Check_Mark                   = 18, // Checkbox tick and RadioButton circle
	Slider_Grab                  = 19,
	Slider_Grab_Active           = 20,
	Button                       = 21,
	Button_Hovered               = 22,
	Button_Active                = 23,
	Header                       = 24, // Header* colors are used for CollapsingHeader, TreeNode, Selectable, MenuItem
	Header_Hovered               = 25,
	Header_Active                = 26,
	Separator                    = 27,
	Separator_Hovered            = 28,
	Separator_Active             = 29,
	Resize_Grip                  = 30, // Resize grip in lower-right and lower-left corners of windows.
	Resize_Grip_Hovered          = 31,
	Resize_Grip_Active           = 32,
	Tab_Hovered                  = 33, // Tab background, when hovered
	Tab                          = 34, // Tab background, when tab-bar is focused & tab is unselected
	Tab_Selected                 = 35, // Tab background, when tab-bar is focused & tab is selected
	Tab_Selected_Overline        = 36, // Tab horizontal overline, when tab-bar is focused & tab is selected
	Tab_Dimmed                   = 37, // Tab background, when tab-bar is unfocused & tab is unselected
	Tab_Dimmed_Selected          = 38, // Tab background, when tab-bar is unfocused & tab is selected
	Tab_Dimmed_Selected_Overline = 39, //..horizontal overline, when tab-bar is unfocused & tab is selected
	Docking_Preview              = 40, // Preview overlay color when about to docking something
	Docking_Empty_Bg             = 41, // Background color for empty node (e.g. CentralNode with no window docked into it)
	Plot_Lines                   = 42,
	Plot_Lines_Hovered           = 43,
	Plot_Histogram               = 44,
	Plot_Histogram_Hovered       = 45,
	Table_Header_Bg              = 46, // Table header background
	Table_Border_Strong          = 47, // Table outer and header borders (prefer using Alpha=1.0 here)
	Table_Border_Light           = 48, // Table inner borders (prefer using Alpha=1.0 here)
	Table_Row_Bg                 = 49, // Table row background (even rows)
	Table_Row_Bg_Alt             = 50, // Table row background (odd rows)
	Text_Link                    = 51, // Hyperlink color
	Text_Selected_Bg             = 52,
	Drag_Drop_Target             = 53, // Rectangle highlighting a drop target
	Nav_Cursor                   = 54, // Color of keyboard/gamepad navigation cursor/rectangle, when visible
	Nav_Windowing_Highlight      = 55, // Highlight window when using CTRL+TAB
	Nav_Windowing_Dim_Bg         = 56, // Darken/colorize entire screen behind the CTRL+TAB window list, when active
	Modal_Window_Dim_Bg          = 57, // Darken/colorize entire screen behind a modal window, when one is active
}

COL_COUNT :: 58

// Enumeration for PushStyleVar() / PopStyleVar() to temporarily modify the ImGuiStyle structure.
// - The enum only refers to fields of ImGuiStyle which makes sense to be pushed/popped inside UI code.
//   During initialization or between frames, feel free to just poke into ImGuiStyle directly.
// - Tip: Use your programming IDE navigation facilities on the names in the _second column_ below to find the actual members and their description.
//   - In Visual Studio: CTRL+comma ("Edit.GoToAll") can follow symbols inside comments, whereas CTRL+F12 ("Edit.GoToImplementation") cannot.
//   - In Visual Studio w/ Visual Assist installed: ALT+G ("VAssistX.GoToImplementation") can also follow symbols inside comments.
//   - In VS Code, CLion, etc.: CTRL+click can follow symbols inside comments.
// - When changing this enum, you need to update the associated internal table GStyleVarInfo[] accordingly. This is where we link enum values to members offset/type.
Style_Var :: enum i32 {
	Alpha                           = 0, // float     Alpha
	Disabled_Alpha                  = 1, // float     DisabledAlpha
	Window_Padding                  = 2, // ImVec2    WindowPadding
	Window_Rounding                 = 3, // float     WindowRounding
	Window_Border_Size              = 4, // float     WindowBorderSize
	Window_Min_Size                 = 5, // ImVec2    WindowMinSize
	Window_Title_Align              = 6, // ImVec2    WindowTitleAlign
	Child_Rounding                  = 7, // float     ChildRounding
	Child_Border_Size               = 8, // float     ChildBorderSize
	Popup_Rounding                  = 9, // float     PopupRounding
	Popup_Border_Size               = 10, // float     PopupBorderSize
	Frame_Padding                   = 11, // ImVec2    FramePadding
	Frame_Rounding                  = 12, // float     FrameRounding
	Frame_Border_Size               = 13, // float     FrameBorderSize
	Item_Spacing                    = 14, // ImVec2    ItemSpacing
	Item_Inner_Spacing              = 15, // ImVec2    ItemInnerSpacing
	Indent_Spacing                  = 16, // float     IndentSpacing
	Cell_Padding                    = 17, // ImVec2    CellPadding
	Scrollbar_Size                  = 18, // float     ScrollbarSize
	Scrollbar_Rounding              = 19, // float     ScrollbarRounding
	Grab_Min_Size                   = 20, // float     GrabMinSize
	Grab_Rounding                   = 21, // float     GrabRounding
	Image_Border_Size               = 22, // float     ImageBorderSize
	Tab_Rounding                    = 23, // float     TabRounding
	Tab_Border_Size                 = 24, // float     TabBorderSize
	Tab_Bar_Border_Size             = 25, // float     TabBarBorderSize
	Tab_Bar_Overline_Size           = 26, // float     TabBarOverlineSize
	Table_Angled_Headers_Angle      = 27, // float     TableAngledHeadersAngle
	Table_Angled_Headers_Text_Align = 28, // ImVec2  TableAngledHeadersTextAlign
	Button_Text_Align               = 29, // ImVec2    ButtonTextAlign
	Selectable_Text_Align           = 30, // ImVec2    SelectableTextAlign
	Separator_Text_Border_Size      = 31, // float     SeparatorTextBorderSize
	Separator_Text_Align            = 32, // ImVec2    SeparatorTextAlign
	Separator_Text_Padding          = 33, // ImVec2    SeparatorTextPadding
	Docking_Separator_Size          = 34, // float     DockingSeparatorSize
}

STYLE_VAR_COUNT :: 35

// Flags for InvisibleButton() [extended in imgui_internal.h]
Button_Flags :: bit_set[Button_Flag;i32]
Button_Flag :: enum i32 {
	Mouse_Button_Left   = 0, // React on left mouse button (default)
	Mouse_Button_Right  = 1, // React on right mouse button
	Mouse_Button_Middle = 2, // React on center mouse button
	Enable_Nav          = 3, // InvisibleButton(): do not disable navigation/tabbing. Otherwise disabled by default.
}

// Flags for ColorEdit3() / ColorEdit4() / ColorPicker3() / ColorPicker4() / ColorButton()
Color_Edit_Flags :: bit_set[Color_Edit_Flag;i32]
Color_Edit_Flag :: enum i32 {
	No_Alpha           = 1, //              // ColorEdit, ColorPicker, ColorButton: ignore Alpha component (will only read 3 components from the input pointer).
	No_Picker          = 2, //              // ColorEdit: disable picker when clicking on color square.
	No_Options         = 3, //              // ColorEdit: disable toggling options menu when right-clicking on inputs/small preview.
	No_Small_Preview   = 4, //              // ColorEdit, ColorPicker: disable color square preview next to the inputs. (e.g. to show only the inputs)
	No_Inputs          = 5, //              // ColorEdit, ColorPicker: disable inputs sliders/text widgets (e.g. to show only the small preview color square).
	No_Tooltip         = 6, //              // ColorEdit, ColorPicker, ColorButton: disable tooltip when hovering the preview.
	No_Label           = 7, //              // ColorEdit, ColorPicker: disable display of inline text label (the label is still forwarded to the tooltip and picker).
	No_Side_Preview    = 8, //              // ColorPicker: disable bigger color preview on right side of the picker, use small color square preview instead.
	No_Drag_Drop       = 9, //              // ColorEdit: disable drag and drop target. ColorButton: disable drag and drop source.
	No_Border          = 10, //              // ColorButton: disable border (which is enforced by default)
	Alpha_Opaque       = 11, //              // ColorEdit, ColorPicker, ColorButton: disable alpha in the preview,. Contrary to _NoAlpha it may still be edited when calling ColorEdit4()/ColorPicker4(). For ColorButton() this does the same as _NoAlpha.
	Alpha_No_Bg        = 12, //              // ColorEdit, ColorPicker, ColorButton: disable rendering a checkerboard background behind transparent color.
	Alpha_Preview_Half = 13, //              // ColorEdit, ColorPicker, ColorButton: display half opaque / half transparent preview.
	Alpha_Bar          = 16, //              // ColorEdit, ColorPicker: show vertical alpha bar/gradient in picker.
	HDR                = 19, //              // (WIP) ColorEdit: Currently only disable 0.0f..1.0f limits in RGBA edition (note: you probably want to use ImGuiColorEditFlags_Float flag as well).
	Display_RGB        = 20, // [Display]    // ColorEdit: override _display_ type among RGB/HSV/Hex. ColorPicker: select any combination using one or more of RGB/HSV/Hex.
	Display_HSV        = 21, // [Display]    // "
	Display_Hex        = 22, // [Display]    // "
	Uint8              = 23, // [DataType]   // ColorEdit, ColorPicker, ColorButton: _display_ values formatted as 0..255.
	Float              = 24, // [DataType]   // ColorEdit, ColorPicker, ColorButton: _display_ values formatted as 0.0f..1.0f floats instead of 0..255 integers. No round-trip of value via integers.
	Picker_Hue_Bar     = 25, // [Picker]     // ColorPicker: bar for Hue, rectangle for Sat/Value.
	Picker_Hue_Wheel   = 26, // [Picker]     // ColorPicker: wheel for Hue, triangle for Sat/Value.
	Input_RGB          = 27, // [Input]      // ColorEdit, ColorPicker: input and output data in RGB format.
	Input_HSV          = 28, // [Input]      // ColorEdit, ColorPicker: input and output data in HSV format.
}

// Flags for DragFloat(), DragInt(), SliderFloat(), SliderInt() etc.
// We use the same sets of flags for DragXXX() and SliderXXX() functions as the features are the same and it makes it easier to swap them.
// (Those are per-item flags. There is shared behavior flag too: ImGuiIO: io.ConfigDragClickToInputText)
Slider_Flags :: bit_set[Slider_Flag;i32]
Slider_Flag :: enum i32 {
	Logarithmic        = 5, // Make the widget logarithmic (linear otherwise). Consider using ImGuiSliderFlags_NoRoundToFormat with this if using a format-string with small amount of digits.
	No_Round_To_Format = 6, // Disable rounding underlying value to match precision of the display format string (e.g. %.3f values are rounded to those 3 digits).
	No_Input           = 7, // Disable CTRL+Click or Enter key allowing to input text directly into the widget.
	Wrap_Around        = 8, // Enable wrapping around from max to min and from min to max. Only supported by DragXXX() functions for now.
	Clamp_On_Input     = 9, // Clamp value to min/max bounds when input manually with CTRL+Click. By default CTRL+Click allows going out of bounds.
	Clamp_Zero_Range   = 10, // Clamp even if min==max==0.0f. Otherwise due to legacy reason DragXXX functions don't clamp with those values. When your clamping limits are dynamic you almost always want to use it.
	No_Speed_Tweaks    = 11, // Disable keyboard modifiers altering tweak speed. Useful if you want to alter tweak speed yourself based on your own logic.
}

SLIDER_FLAGS_ALWAYS_CLAMP :: Slider_Flags{.Clamp_On_Input, .Clamp_Zero_Range}

// Identify a mouse button.
// Those values are guaranteed to be stable and we frequently use 0/1 directly. Named enums provided for convenience.
Mouse_Button :: enum i32 {
	Left   = 0,
	Right  = 1,
	Middle = 2,
}

MOUSE_BUTTON_COUNT :: 5

// Enumeration for GetMouseCursor()
// User code may request backend to display given cursor by calling SetMouseCursor(), which is why we have some cursors that are marked unused here
Mouse_Cursor :: enum i32 {
	None        = -1,
	Arrow       = 0,
	Text_Input  = 1, // When hovering over InputText, etc.
	Resize_All  = 2, // (Unused by Dear ImGui functions)
	Resize_NS   = 3, // When hovering over a horizontal border
	Resize_EW   = 4, // When hovering over a vertical border or a column
	Resize_NESW = 5, // When hovering over the bottom-left corner of a window
	Resize_NWSE = 6, // When hovering over the bottom-right corner of a window
	Hand        = 7, // (Unused by Dear ImGui functions. Use for e.g. hyperlinks)
	Wait        = 8, // When waiting for something to process/load.
	Progress    = 9, // When waiting for something to process/load, but application is still interactive.
	Not_Allowed = 10, // When hovering something with disallowed interaction. Usually a crossed circle.
}

MOUSE_CURSOR_COUNT :: 11

// Enumeration for AddMouseSourceEvent() actual source of Mouse Input data.
// Historically we use "Mouse" terminology everywhere to indicate pointer data, e.g. MousePos, IsMousePressed(), io.AddMousePosEvent()
// But that "Mouse" data can come from different source which occasionally may be useful for application to know about.
// You can submit a change of pointer type using io.AddMouseSourceEvent().
Mouse_Source :: enum i32 {
	Mouse        = 0, // Input is coming from an actual mouse.
	Touch_Screen = 1, // Input is coming from a touch screen (no hovering prior to initial press, less precise initial press aiming, dual-axis wheeling possible).
	Pen          = 2, // Input is coming from a pressure/magnetic pen (often used in conjunction with high-sampling rates).
}

MOUSE_SOURCE_COUNT :: 3

// Enumeration for ImGui::SetNextWindow***(), SetWindow***(), SetNextItem***() functions
// Represent a condition.
// Important: Treat as a regular enum! Do NOT combine multiple values using binary operators! All the functions above treat 0 as a shortcut to ImGuiCond_Always.
Cond :: enum i32 {
	None           = 0, // No condition (always set the variable), same as _Always
	Always         = 1, // No condition (always set the variable), same as _None
	Once           = 2, // Set the variable once per runtime session (only the first call will succeed)
	First_Use_Ever = 4, // Set the variable if the object/window has no persistently saved data (no entry in .ini file)
	Appearing      = 8, // Set the variable if the object/window is appearing after being hidden/inactive (or the first time)
}

// Flags for ImGui::BeginTable()
// - Important! Sizing policies have complex and subtle side effects, much more so than you would expect.
//   Read comments/demos carefully + experiment with live demos to get acquainted with them.
// - The DEFAULT sizing policies are:
//    - Default to ImGuiTableFlags_SizingFixedFit    if ScrollX is on, or if host window has ImGuiWindowFlags_AlwaysAutoResize.
//    - Default to ImGuiTableFlags_SizingStretchSame if ScrollX is off.
// - When ScrollX is off:
//    - Table defaults to ImGuiTableFlags_SizingStretchSame -> all Columns defaults to ImGuiTableColumnFlags_WidthStretch with same weight.
//    - Columns sizing policy allowed: Stretch (default), Fixed/Auto.
//    - Fixed Columns (if any) will generally obtain their requested width (unless the table cannot fit them all).
//    - Stretch Columns will share the remaining width according to their respective weight.
//    - Mixed Fixed/Stretch columns is possible but has various side-effects on resizing behaviors.
//      The typical use of mixing sizing policies is: any number of LEADING Fixed columns, followed by one or two TRAILING Stretch columns.
//      (this is because the visible order of columns have subtle but necessary effects on how they react to manual resizing).
// - When ScrollX is on:
//    - Table defaults to ImGuiTableFlags_SizingFixedFit -> all Columns defaults to ImGuiTableColumnFlags_WidthFixed
//    - Columns sizing policy allowed: Fixed/Auto mostly.
//    - Fixed Columns can be enlarged as needed. Table will show a horizontal scrollbar if needed.
//    - When using auto-resizing (non-resizable) fixed columns, querying the content width to use item right-alignment e.g. SetNextItemWidth(-FLT_MIN) doesn't make sense, would create a feedback loop.
//    - Using Stretch columns OFTEN DOES NOT MAKE SENSE if ScrollX is on, UNLESS you have specified a value for 'inner_width' in BeginTable().
//      If you specify a value for 'inner_width' then effectively the scrolling space is known and Stretch or mixed Fixed/Stretch columns become meaningful again.
// - Read on documentation at the top of imgui_tables.cpp for details.
Table_Flags :: bit_set[Table_Flag;i32]
Table_Flag :: enum i32 {
	Resizable                       = 0, // Enable resizing columns.
	Reorderable                     = 1, // Enable reordering columns in header row (need calling TableSetupColumn() + TableHeadersRow() to display headers)
	Hideable                        = 2, // Enable hiding/disabling columns in context menu.
	Sortable                        = 3, // Enable sorting. Call TableGetSortSpecs() to obtain sort specs. Also see ImGuiTableFlags_SortMulti and ImGuiTableFlags_SortTristate.
	No_Saved_Settings               = 4, // Disable persisting columns order, width and sort settings in the .ini file.
	Context_Menu_In_Body            = 5, // Right-click on columns body/contents will display table context menu. By default it is available in TableHeadersRow().
	Row_Bg                          = 6, // Set each RowBg color with ImGuiCol_TableRowBg or ImGuiCol_TableRowBgAlt (equivalent of calling TableSetBgColor with ImGuiTableBgFlags_RowBg0 on each row manually)
	Borders_Inner_H                 = 7, // Draw horizontal borders between rows.
	Borders_Outer_H                 = 8, // Draw horizontal borders at the top and bottom.
	Borders_Inner_V                 = 9, // Draw vertical borders between columns.
	Borders_Outer_V                 = 10, // Draw vertical borders on the left and right sides.
	No_Borders_In_Body              = 11, // [ALPHA] Disable vertical borders in columns Body (borders will always appear in Headers). -> May move to style
	No_Borders_In_Body_Until_Resize = 12, // [ALPHA] Disable vertical borders in columns Body until hovered for resize (borders will always appear in Headers). -> May move to style
	Sizing_Fixed_Fit                = 13, // Columns default to _WidthFixed or _WidthAuto (if resizable or not resizable), matching contents width.
	Sizing_Fixed_Same               = 14, // Columns default to _WidthFixed or _WidthAuto (if resizable or not resizable), matching the maximum contents width of all columns. Implicitly enable ImGuiTableFlags_NoKeepColumnsVisible.
	Sizing_Stretch_Prop             = 13, // Columns default to _WidthStretch with default weights proportional to each columns contents widths.
	Sizing_Stretch_Same             = 15, // Columns default to _WidthStretch with default weights all equal, unless overridden by TableSetupColumn().
	No_Host_Extend_X                = 16, // Make outer width auto-fit to columns, overriding outer_size.x value. Only available when ScrollX/ScrollY are disabled and Stretch columns are not used.
	No_Host_Extend_Y                = 17, // Make outer height stop exactly at outer_size.y (prevent auto-extending table past the limit). Only available when ScrollX/ScrollY are disabled. Data below the limit will be clipped and not visible.
	No_Keep_Columns_Visible         = 18, // Disable keeping column always minimally visible when ScrollX is off and table gets too small. Not recommended if columns are resizable.
	Precise_Widths                  = 19, // Disable distributing remainder width to stretched columns (width allocation on a 100-wide table with 3 columns: Without this flag: 33,33,34. With this flag: 33,33,33). With larger number of columns, resizing will appear to be less smooth.
	No_Clip                         = 20, // Disable clipping rectangle for every individual columns (reduce draw command count, items will be able to overflow into other columns). Generally incompatible with TableSetupScrollFreeze().
	Pad_Outer_X                     = 21, // Default if BordersOuterV is on. Enable outermost padding. Generally desirable if you have headers.
	No_Pad_Outer_X                  = 22, // Default if BordersOuterV is off. Disable outermost padding.
	No_Pad_Inner_X                  = 23, // Disable inner padding between columns (double inner padding if BordersOuterV is on, single inner padding if BordersOuterV is off).
	Scroll_X                        = 24, // Enable horizontal scrolling. Require 'outer_size' parameter of BeginTable() to specify the container size. Changes default sizing policy. Because this creates a child window, ScrollY is currently generally recommended when using ScrollX.
	Scroll_Y                        = 25, // Enable vertical scrolling. Require 'outer_size' parameter of BeginTable() to specify the container size.
	Sort_Multi                      = 26, // Hold shift when clicking headers to sort on multiple column. TableGetSortSpecs() may return specs where (SpecsCount > 1).
	Sort_Tristate                   = 27, // Allow no sorting, disable default sorting. TableGetSortSpecs() may return specs where (SpecsCount == 0).
	Highlight_Hovered_Column        = 28, // Highlight column headers when hovered (may evolve into a fuller highlight)
}

TABLE_FLAGS_BORDERS_H :: Table_Flags{.Borders_Inner_H, .Borders_Outer_H}
TABLE_FLAGS_BORDERS_V :: Table_Flags{.Borders_Inner_V, .Borders_Outer_V}
TABLE_FLAGS_BORDERS_INNER :: Table_Flags{.Borders_Inner_V, .Borders_Inner_H}
TABLE_FLAGS_BORDERS_OUTER :: Table_Flags{.Borders_Outer_V, .Borders_Outer_H}
TABLE_FLAGS_BORDERS :: Table_Flags {
	.Borders_Inner_V,
	.Borders_Inner_H,
	.Borders_Outer_V,
	.Borders_Outer_H,
}

// Flags for ImGui::TableSetupColumn()
Table_Column_Flags :: bit_set[Table_Column_Flag;i32]
Table_Column_Flag :: enum i32 {
	Disabled               = 0, // Overriding/master disable flag: hide column, won't show in context menu (unlike calling TableSetColumnEnabled() which manipulates the user accessible state)
	Default_Hide           = 1, // Default as a hidden/disabled column.
	Default_Sort           = 2, // Default as a sorting column.
	Width_Stretch          = 3, // Column will stretch. Preferable with horizontal scrolling disabled (default if table sizing policy is _SizingStretchSame or _SizingStretchProp).
	Width_Fixed            = 4, // Column will not stretch. Preferable with horizontal scrolling enabled (default if table sizing policy is _SizingFixedFit and table is resizable).
	No_Resize              = 5, // Disable manual resizing.
	No_Reorder             = 6, // Disable manual reordering this column, this will also prevent other columns from crossing over this column.
	No_Hide                = 7, // Disable ability to hide/disable this column.
	No_Clip                = 8, // Disable clipping for this column (all NoClip columns will render in a same draw command).
	No_Sort                = 9, // Disable ability to sort on this field (even if ImGuiTableFlags_Sortable is set on the table).
	No_Sort_Ascending      = 10, // Disable ability to sort in the ascending direction.
	No_Sort_Descending     = 11, // Disable ability to sort in the descending direction.
	No_Header_Label        = 12, // TableHeadersRow() will submit an empty label for this column. Convenient for some small columns. Name will still appear in context menu or in angled headers. You may append into this cell by calling TableSetColumnIndex() right after the TableHeadersRow() call.
	No_Header_Width        = 13, // Disable header text width contribution to automatic column width.
	Prefer_Sort_Ascending  = 14, // Make the initial sort direction Ascending when first sorting on this column (default).
	Prefer_Sort_Descending = 15, // Make the initial sort direction Descending when first sorting on this column.
	Indent_Enable          = 16, // Use current Indent value when entering cell (default for column 0).
	Indent_Disable         = 17, // Ignore current Indent value when entering cell (default for columns > 0). Indentation changes _within_ the cell will still be honored.
	Angled_Header          = 18, // TableHeadersRow() will submit an angled header row for this column. Note this will add an extra row.
	Is_Enabled             = 24, // Status: is enabled == not hidden by user/api (referred to as "Hide" in _DefaultHide and _NoHide) flags.
	Is_Visible             = 25, // Status: is visible == is enabled AND not clipped by scrolling.
	Is_Sorted              = 26, // Status: is currently part of the sort specs
	Is_Hovered             = 27, // Status: is hovered by mouse
}

// Flags for ImGui::TableNextRow()
Table_Row_Flags :: bit_set[Table_Row_Flag;i32]
Table_Row_Flag :: enum i32 {
	Headers = 0, // Identify header row (set default background color + width of its contents accounted differently for auto column width)
}

// Enum for ImGui::TableSetBgColor()
// Background colors are rendering in 3 layers:
//  - Layer 0: draw with RowBg0 color if set, otherwise draw with ColumnBg0 if set.
//  - Layer 1: draw with RowBg1 color if set, otherwise draw with ColumnBg1 if set.
//  - Layer 2: draw with CellBg color if set.
// The purpose of the two row/columns layers is to let you decide if a background color change should override or blend with the existing color.
// When using ImGuiTableFlags_RowBg on the table, each row has the RowBg0 color automatically set for odd/even rows.
// If you set the color of RowBg0 target, your color will override the existing RowBg0 color.
// If you set the color of RowBg1 or ColumnBg1 target, your color will blend over the RowBg0 color.
Table_Bg_Target :: enum i32 {
	None    = 0,
	Row_Bg0 = 1, // Set row background color 0 (generally used for background, automatically set when ImGuiTableFlags_RowBg is used)
	Row_Bg1 = 2, // Set row background color 1 (generally used for selection marking)
	Cell_Bg = 3, // Set cell background color (top-most color)
}

// Flags for BeginMultiSelect()
Multi_Select_Flags :: bit_set[Multi_Select_Flag;i32]
Multi_Select_Flag :: enum i32 {
	Single_Select             = 0, // Disable selecting more than one item. This is available to allow single-selection code to share same code/logic if desired. It essentially disables the main purpose of BeginMultiSelect() tho!
	No_Select_All             = 1, // Disable CTRL+A shortcut to select all.
	No_Range_Select           = 2, // Disable Shift+selection mouse/keyboard support (useful for unordered 2D selection). With BoxSelect is also ensure contiguous SetRange requests are not combined into one. This allows not handling interpolation in SetRange requests.
	No_Auto_Select            = 3, // Disable selecting items when navigating (useful for e.g. supporting range-select in a list of checkboxes).
	No_Auto_Clear             = 4, // Disable clearing selection when navigating or selecting another one (generally used with ImGuiMultiSelectFlags_NoAutoSelect. useful for e.g. supporting range-select in a list of checkboxes).
	No_Auto_Clear_On_Reselect = 5, // Disable clearing selection when clicking/selecting an already selected item.
	Box_Select1d              = 6, // Enable box-selection with same width and same x pos items (e.g. full row Selectable()). Box-selection works better with little bit of spacing between items hit-box in order to be able to aim at empty space.
	Box_Select2d              = 7, // Enable box-selection with varying width or varying x pos items support (e.g. different width labels, or 2D layout/grid). This is slower: alters clipping logic so that e.g. horizontal movements will update selection of normally clipped items.
	Box_Select_No_Scroll      = 8, // Disable scrolling when box-selecting near edges of scope.
	Clear_On_Escape           = 9, // Clear selection when pressing Escape while scope is focused.
	Clear_On_Click_Void       = 10, // Clear selection when clicking on empty location within scope.
	Scope_Window              = 11, // Scope for _BoxSelect and _ClearOnClickVoid is whole window (Default). Use if BeginMultiSelect() covers a whole window or used a single time in same window.
	Scope_Rect                = 12, // Scope for _BoxSelect and _ClearOnClickVoid is rectangle encompassing BeginMultiSelect()/EndMultiSelect(). Use if BeginMultiSelect() is called multiple times in same window.
	Select_On_Click           = 13, // Apply selection on mouse down when clicking on unselected item. (Default)
	Select_On_Click_Release   = 14, // Apply selection on mouse release when clicking an unselected item. Allow dragging an unselected item without altering selection.
	Nav_Wrap_X                = 16, // [Temporary] Enable navigation wrapping on X axis. Provided as a convenience because we don't have a design for the general Nav API for this yet. When the more general feature be public we may obsolete this flag in favor of new one.
}

// Selection request type
Selection_Request_Type :: enum i32 {
	None      = 0,
	Set_All   = 1, // Request app to clear selection (if Selected==false) or select all items (if Selected==true). We cannot set RangeFirstItem/RangeLastItem as its contents is entirely up to user (not necessarily an index)
	Set_Range = 2, // Request app to select/unselect [RangeFirstItem..RangeLastItem] items (inclusive) based on value of Selected. Only EndMultiSelect() request this, app code can read after BeginMultiSelect() and it will always be false.
}

// Flags for ImDrawList functions
// (Legacy: bit 0 must always correspond to ImDrawFlags_Closed to be backward compatible with old API using a bool. Bits 1..3 must be unused)
Draw_Flags :: bit_set[Draw_Flag;i32]
Draw_Flag :: enum i32 {
	Closed                     = 0, // PathStroke(), AddPolyline(): specify that shape should be closed (Important: this is always == 1 for legacy reason)
	Round_Corners_Top_Left     = 4, // AddRect(), AddRectFilled(), PathRect(): enable rounding top-left corner only (when rounding > 0.0f, we default to all corners). Was 0x01.
	Round_Corners_Top_Right    = 5, // AddRect(), AddRectFilled(), PathRect(): enable rounding top-right corner only (when rounding > 0.0f, we default to all corners). Was 0x02.
	Round_Corners_Bottom_Left  = 6, // AddRect(), AddRectFilled(), PathRect(): enable rounding bottom-left corner only (when rounding > 0.0f, we default to all corners). Was 0x04.
	Round_Corners_Bottom_Right = 7, // AddRect(), AddRectFilled(), PathRect(): enable rounding bottom-right corner only (when rounding > 0.0f, we default to all corners). Wax 0x08.
	Round_Corners_None         = 8, // AddRect(), AddRectFilled(), PathRect(): disable rounding on all corners (when rounding > 0.0f). This is NOT zero, NOT an implicit flag!
}

DRAW_FLAGS_ROUND_CORNERS_TOP :: Draw_Flags{.Round_Corners_Top_Left, .Round_Corners_Top_Right}
DRAW_FLAGS_ROUND_CORNERS_BOTTOM :: Draw_Flags {
	.Round_Corners_Bottom_Left,
	.Round_Corners_Bottom_Right,
}
DRAW_FLAGS_ROUND_CORNERS_LEFT :: Draw_Flags{.Round_Corners_Bottom_Left, .Round_Corners_Top_Left}
DRAW_FLAGS_ROUND_CORNERS_RIGHT :: Draw_Flags{.Round_Corners_Bottom_Right, .Round_Corners_Top_Right}
DRAW_FLAGS_ROUND_CORNERS_ALL :: Draw_Flags {
	.Round_Corners_Top_Left,
	.Round_Corners_Top_Right,
	.Round_Corners_Bottom_Left,
	.Round_Corners_Bottom_Right,
}

// Flags for ImDrawList instance. Those are set automatically by ImGui:: functions from ImGuiIO settings, and generally not manipulated directly.
// It is however possible to temporarily alter flags between calls to ImDrawList:: functions.
Draw_List_Flags :: bit_set[Draw_List_Flag;i32]
Draw_List_Flag :: enum i32 {
	Anti_Aliased_Lines         = 0, // Enable anti-aliased lines/borders (*2 the number of triangles for 1.0f wide line or lines thin enough to be drawn using textures, otherwise *3 the number of triangles)
	Anti_Aliased_Lines_Use_Tex = 1, // Enable anti-aliased lines/borders using textures when possible. Require backend to render with bilinear filtering (NOT point/nearest filtering).
	Anti_Aliased_Fill          = 2, // Enable anti-aliased edge around filled shapes (rounded rectangles, circles).
	Allow_Vtx_Offset           = 3, // Can emit 'VtxOffset > 0' to allow large meshes. Set when 'ImGuiBackendFlags_RendererHasVtxOffset' is enabled.
}

// Flags for ImFontAtlas build
Font_Atlas_Flags :: bit_set[Font_Atlas_Flag;i32]
Font_Atlas_Flag :: enum i32 {
	No_Power_Of_Two_Height = 0, // Don't round the height to next power of two
	No_Mouse_Cursors       = 1, // Don't build software mouse cursors into the atlas (save a little texture memory)
	No_Baked_Lines         = 2, // Don't build thick line textures into the atlas (save a little texture memory, allow support for point/nearest filtering). The AntiAliasedLinesUseTex features uses them, otherwise they will be rendered using polygons (more expensive for CPU/GPU).
}

// Flags stored in ImGuiViewport::Flags, giving indications to the platform backends.
Viewport_Flags :: bit_set[Viewport_Flag;i32]
Viewport_Flag :: enum i32 {
	Is_Platform_Window     = 0, // Represent a Platform Window
	Is_Platform_Monitor    = 1, // Represent a Platform Monitor (unused yet)
	Owned_By_App           = 2, // Platform Window: Is created/managed by the user application? (rather than our backend)
	No_Decoration          = 3, // Platform Window: Disable platform decorations: title bar, borders, etc. (generally set all windows, but if ImGuiConfigFlags_ViewportsDecoration is set we only set this on popups/tooltips)
	No_Task_Bar_Icon       = 4, // Platform Window: Disable platform task bar icon (generally set on popups/tooltips, or all windows if ImGuiConfigFlags_ViewportsNoTaskBarIcon is set)
	No_Focus_On_Appearing  = 5, // Platform Window: Don't take focus when created.
	No_Focus_On_Click      = 6, // Platform Window: Don't take focus when clicked on.
	No_Inputs              = 7, // Platform Window: Make mouse pass through so we can drag this window while peaking behind it.
	No_Renderer_Clear      = 8, // Platform Window: Renderer doesn't need to clear the framebuffer ahead (because we will fill it entirely).
	No_Auto_Merge          = 9, // Platform Window: Avoid merging this window into another host window. This can only be set via ImGuiWindowClass viewport flags override (because we need to now ahead if we are going to create a viewport in the first place!).
	Top_Most               = 10, // Platform Window: Display on top (for tooltips only).
	Can_Host_Other_Windows = 11, // Viewport can host multiple imgui windows (secondary viewports are associated to a single window). // FIXME: In practice there's still probably code making the assumption that this is always and only on the MainViewport. Will fix once we add support for "no main viewport".
	Is_Minimized           = 12, // Platform Window: Window is minimized, can skip render. When minimized we tend to avoid using the viewport pos/size for clipping window or testing if they are contained in the viewport.
	Is_Focused             = 13, // Platform Window: Window is focused (last call to Platform_GetWindowFocus() returned true)
}

ID :: u32
Key_Chord :: i32
Texture_ID :: u64
Draw_Idx :: u16
Wchar32 :: u32
Wchar16 :: u16
Wchar :: Wchar32
Selection_User_Data :: i64
Input_Text_Callback :: #type proc(data: ^Input_Text_Callback_Data) -> i32
Size_Callback :: #type proc(data: ^Size_Callback_Data)
Mem_Alloc_Func :: #type proc(sz: uint, user_data: rawptr) -> rawptr
Mem_Free_Func :: #type proc(ptr: rawptr, user_data: rawptr)
Draw_Callback :: #type proc(parent_list: ^Draw_List, cmd: ^Draw_Cmd)

Draw_List_Shared_Data :: struct {}

Font_Builder_IO :: struct {}

// Forward declarations: ImGui layer
Context :: struct {}

Vec2 :: struct {
	x: f32,
	y: f32,
}

// ImVec4: 4D vector used to store clipping rectangles, colors etc. [Compile-time configurable type]
Vec4 :: struct {
	x: f32,
	y: f32,
	z: f32,
	w: f32,
}

// Sorting specifications for a table (often handling sort specs for a single column, occasionally more)
// Obtained by calling TableGetSortSpecs().
// When 'SpecsDirty == true' you can sort your data. It will be true with sorting specs have changed since last call, or the first time.
// Make sure to set 'SpecsDirty = false' after sorting, else you may wastefully sort your data every frame!
Table_Sort_Specs :: struct {
	specs:       ^Table_Column_Sort_Specs, // Pointer to sort spec array.
	specs_count: i32, // Sort spec count. Most often 1. May be > 1 when ImGuiTableFlags_SortMulti is enabled. May be == 0 when ImGuiTableFlags_SortTristate is enabled.
	specs_dirty: bool, // Set to true when specs have changed since last time! Use this to sort again, then clear the flag.
}

// Sorting specification for one column of a table (sizeof == 12 bytes)
Table_Column_Sort_Specs :: struct {
	column_user_id: ID, // User id of the column (if specified by a TableSetupColumn() call)
	column_index:   i16, // Index of the column
	sort_order:     i16, // Index within parent ImGuiTableSortSpecs (always stored in order starting from 0, tables sorted on a single criteria will always have a 0 here)
	sort_direction: Sort_Direction, // ImGuiSortDirection_Ascending or ImGuiSortDirection_Descending
}

Vector_Wchar :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Wchar,
}

Vector_Gui_Text_Filter_Gui_Text_Range :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Text_Filter_Gui_Text_Range,
}

Vector_char :: struct {
	size:     i32,
	capacity: i32,
	data:     cstring,
}

Vector_Gui_Storage_Pair :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Storage_Pair,
}

Vector_Gui_Selection_Request :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Selection_Request,
}

Vector_Draw_Cmd :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Draw_Cmd,
}

Vector_Draw_Idx :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Draw_Idx,
}

Vector_Draw_Channel :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Draw_Channel,
}

Vector_Draw_Vert :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Draw_Vert,
}

Vector_Vec2 :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Vec2,
}

Vector_Vec4 :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Vec4,
}

Vector_Texture_ID :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Texture_ID,
}

Vector_U8 :: struct {
	size:     i32,
	capacity: i32,
	data:     ^u8,
}

Vector_Draw_List_Ptr :: struct {
	size:     i32,
	capacity: i32,
	data:     ^^Draw_List,
}

Vector_U32 :: struct {
	size:     i32,
	capacity: i32,
	data:     ^u32,
}

Vector_Font_Ptr :: struct {
	size:     i32,
	capacity: i32,
	data:     ^^Font,
}

Vector_Font_Atlas_Custom_Rect :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Font_Atlas_Custom_Rect,
}

Vector_Font_Config :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Font_Config,
}

Vector_float :: struct {
	size:     i32,
	capacity: i32,
	data:     ^f32,
}

Vector_U16 :: struct {
	size:     i32,
	capacity: i32,
	data:     ^u16,
}

Vector_Font_Glyph :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Font_Glyph,
}

Vector_Gui_Platform_Monitor :: struct {
	size:     i32,
	capacity: i32,
	data:     ^Platform_Monitor,
}

Vector_Gui_Viewport_Ptr :: struct {
	size:     i32,
	capacity: i32,
	data:     ^^Viewport,
}

Style :: struct {
	alpha:                                 f32, // Global alpha applies to everything in Dear ImGui.
	disabled_alpha:                        f32, // Additional alpha multiplier applied by BeginDisabled(). Multiply over current value of Alpha.
	window_padding:                        Vec2, // Padding within a window.
	window_rounding:                       f32, // Radius of window corners rounding. Set to 0.0f to have rectangular windows. Large values tend to lead to variety of artifacts and are not recommended.
	window_border_size:                    f32, // Thickness of border around windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	window_border_hover_padding:           f32, // Hit-testing extent outside/inside resizing border. Also extend determination of hovered window. Generally meaningfully larger than WindowBorderSize to make it easy to reach borders.
	window_min_size:                       Vec2, // Minimum window size. This is a global setting. If you want to constrain individual windows, use SetNextWindowSizeConstraints().
	window_title_align:                    Vec2, // Alignment for title bar text. Defaults to (0.0f,0.5f) for left-aligned,vertically centered.
	window_menu_button_position:           Dir, // Side of the collapsing/docking button in the title bar (None/Left/Right). Defaults to ImGuiDir_Left.
	child_rounding:                        f32, // Radius of child window corners rounding. Set to 0.0f to have rectangular windows.
	child_border_size:                     f32, // Thickness of border around child windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	popup_rounding:                        f32, // Radius of popup window corners rounding. (Note that tooltip windows use WindowRounding)
	popup_border_size:                     f32, // Thickness of border around popup/tooltip windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	frame_padding:                         Vec2, // Padding within a framed rectangle (used by most widgets).
	frame_rounding:                        f32, // Radius of frame corners rounding. Set to 0.0f to have rectangular frame (used by most widgets).
	frame_border_size:                     f32, // Thickness of border around frames. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	item_spacing:                          Vec2, // Horizontal and vertical spacing between widgets/lines.
	item_inner_spacing:                    Vec2, // Horizontal and vertical spacing between within elements of a composed widget (e.g. a slider and its label).
	cell_padding:                          Vec2, // Padding within a table cell. Cellpadding.x is locked for entire table. CellPadding.y may be altered between different rows.
	touch_extra_padding:                   Vec2, // Expand reactive bounding box for touch-based system where touch position is not accurate enough. Unfortunately we don't sort widgets so priority on overlap will always be given to the first widget. So don't grow this too much!
	indent_spacing:                        f32, // Horizontal indentation when e.g. entering a tree node. Generally == (FontSize + FramePadding.x*2).
	columns_min_spacing:                   f32, // Minimum horizontal spacing between two columns. Preferably > (FramePadding.x + 1).
	scrollbar_size:                        f32, // Width of the vertical scrollbar, Height of the horizontal scrollbar.
	scrollbar_rounding:                    f32, // Radius of grab corners for scrollbar.
	grab_min_size:                         f32, // Minimum width/height of a grab box for slider/scrollbar.
	grab_rounding:                         f32, // Radius of grabs corners rounding. Set to 0.0f to have rectangular slider grabs.
	log_slider_deadzone:                   f32, // The size in pixels of the dead-zone around zero on logarithmic sliders that cross zero.
	image_border_size:                     f32, // Thickness of border around Image() calls.
	tab_rounding:                          f32, // Radius of upper corners of a tab. Set to 0.0f to have rectangular tabs.
	tab_border_size:                       f32, // Thickness of border around tabs.
	tab_close_button_min_width_selected:   f32, // -1: always visible. 0.0f: visible when hovered. >0.0f: visible when hovered if minimum width.
	tab_close_button_min_width_unselected: f32, // -1: always visible. 0.0f: visible when hovered. >0.0f: visible when hovered if minimum width. FLT_MAX: never show close button when unselected.
	tab_bar_border_size:                   f32, // Thickness of tab-bar separator, which takes on the tab active color to denote focus.
	tab_bar_overline_size:                 f32, // Thickness of tab-bar overline, which highlights the selected tab-bar.
	table_angled_headers_angle:            f32, // Angle of angled headers (supported values range from -50.0f degrees to +50.0f degrees).
	table_angled_headers_text_align:       Vec2, // Alignment of angled headers within the cell
	color_button_position:                 Dir, // Side of the color button in the ColorEdit4 widget (left/right). Defaults to ImGuiDir_Right.
	button_text_align:                     Vec2, // Alignment of button text when button is larger than text. Defaults to (0.5f, 0.5f) (centered).
	selectable_text_align:                 Vec2, // Alignment of selectable text. Defaults to (0.0f, 0.0f) (top-left aligned). It's generally important to keep this left-aligned if you want to lay multiple items on a same line.
	separator_text_border_size:            f32, // Thickness of border in SeparatorText()
	separator_text_align:                  Vec2, // Alignment of text within the separator. Defaults to (0.0f, 0.5f) (left aligned, center).
	separator_text_padding:                Vec2, // Horizontal offset of text from each edge of the separator + spacing on other axis. Generally small values. .y is recommended to be == FramePadding.y.
	display_window_padding:                Vec2, // Apply to regular windows: amount which we enforce to keep visible when moving near edges of your screen.
	display_safe_area_padding:             Vec2, // Apply to every windows, menus, popups, tooltips: amount where we avoid displaying contents. Adjust if you cannot see the edges of your screen (e.g. on a TV where scaling has not been configured).
	docking_separator_size:                f32, // Thickness of resizing border between docked windows
	mouse_cursor_scale:                    f32, // Scale software rendered mouse cursor (when io.MouseDrawCursor is enabled). We apply per-monitor DPI scaling over this scale. May be removed later.
	anti_aliased_lines:                    bool, // Enable anti-aliased lines/borders. Disable if you are really tight on CPU/GPU. Latched at the beginning of the frame (copied to ImDrawList).
	anti_aliased_lines_use_tex:            bool, // Enable anti-aliased lines/borders using textures where possible. Require backend to render with bilinear filtering (NOT point/nearest filtering). Latched at the beginning of the frame (copied to ImDrawList).
	anti_aliased_fill:                     bool, // Enable anti-aliased edges around filled shapes (rounded rectangles, circles, etc.). Disable if you are really tight on CPU/GPU. Latched at the beginning of the frame (copied to ImDrawList).
	curve_tessellation_tol:                f32, // Tessellation tolerance when using PathBezierCurveTo() without a specific number of segments. Decrease for highly tessellated curves (higher quality, more polygons), increase to reduce quality.
	circle_tessellation_max_error:         f32, // Maximum error (in pixels) allowed when using AddCircle()/AddCircleFilled() or drawing rounded corner rectangles with no explicit segment count specified. Decrease for higher quality but more geometry.
	colors:                                [COL_COUNT]Vec4,
	hover_stationary_delay:                f32, // Delay for IsItemHovered(ImGuiHoveredFlags_Stationary). Time required to consider mouse stationary.
	hover_delay_short:                     f32, // Delay for IsItemHovered(ImGuiHoveredFlags_DelayShort). Usually used along with HoverStationaryDelay.
	hover_delay_normal:                    f32, // Delay for IsItemHovered(ImGuiHoveredFlags_DelayNormal). "
	hover_flags_for_tooltip_mouse:         Hovered_Flags, // Default flags when using IsItemHovered(ImGuiHoveredFlags_ForTooltip) or BeginItemTooltip()/SetItemTooltip() while using mouse.
	hover_flags_for_tooltip_nav:           Hovered_Flags, // Default flags when using IsItemHovered(ImGuiHoveredFlags_ForTooltip) or BeginItemTooltip()/SetItemTooltip() while using keyboard/gamepad.
}

// [Internal] Storage used by IsKeyDown(), IsKeyPressed() etc functions.
// If prior to 1.87 you used io.KeysDownDuration[] (which was marked as internal), you should use GetKeyData(key)->DownDuration and *NOT* io.KeysData[key]->DownDuration.
Key_Data :: struct {
	down:               bool, // True for if key is down
	down_duration:      f32, // Duration the key has been down (<0.0f: not pressed, 0.0f: just pressed, >0.0f: time held)
	down_duration_prev: f32, // Last frame duration the key has been down
	analog_value:       f32, // 0.0f..1.0f for gamepad values
}

IO :: struct {
	config_flags:                                         Config_Flags, // = 0              // See ImGuiConfigFlags_ enum. Set by user/application. Keyboard/Gamepad navigation options, etc.
	backend_flags:                                        Backend_Flags, // = 0              // See ImGuiBackendFlags_ enum. Set by backend (imgui_impl_xxx files or custom backend) to communicate features supported by the backend.
	display_size:                                         Vec2, // <unset>          // Main display size, in pixels (generally == GetMainViewport()->Size). May change every frame.
	delta_time:                                           f32, // = 1.0f/60.0f     // Time elapsed since last frame, in seconds. May change every frame.
	ini_saving_rate:                                      f32, // = 5.0f           // Minimum time between saving positions/sizes to .ini file, in seconds.
	ini_filename:                                         cstring, // = "imgui.ini"    // Path to .ini file (important: default "imgui.ini" is relative to current working dir!). Set NULL to disable automatic .ini loading/saving or if you want to manually call LoadIniSettingsXXX() / SaveIniSettingsXXX() functions.
	log_filename:                                         cstring, // = "imgui_log.txt"// Path to .log file (default parameter to ImGui::LogToFile when no file is specified).
	user_data:                                            rawptr, // = NULL           // Store your own data.
	fonts:                                                ^Font_Atlas, // <auto>           // Font atlas: load, rasterize and pack one or more fonts into a single texture.
	font_global_scale:                                    f32, // = 1.0f           // Global scale all fonts
	font_allow_user_scaling:                              bool, // = false          // [OBSOLETE] Allow user scaling text of individual window with CTRL+Wheel.
	font_default:                                         ^Font, // = NULL           // Font to use on NewFrame(). Use NULL to uses Fonts->Fonts[0].
	display_framebuffer_scale:                            Vec2, // = (1, 1)         // For retina display or other situations where window coordinates are different from framebuffer coordinates. This generally ends up in ImDrawData::FramebufferScale.
	config_nav_swap_gamepad_buttons:                      bool, // = false          // Swap Activate<>Cancel (A<>B) buttons, matching typical "Nintendo/Japanese style" gamepad layout.
	config_nav_move_set_mouse_pos:                        bool, // = false          // Directional/tabbing navigation teleports the mouse cursor. May be useful on TV/console systems where moving a virtual mouse is difficult. Will update io.MousePos and set io.WantSetMousePos=true.
	config_nav_capture_keyboard:                          bool, // = true           // Sets io.WantCaptureKeyboard when io.NavActive is set.
	config_nav_escape_clear_focus_item:                   bool, // = true           // Pressing Escape can clear focused item + navigation id/highlight. Set to false if you want to always keep highlight on.
	config_nav_escape_clear_focus_window:                 bool, // = false          // Pressing Escape can clear focused window as well (super set of io.ConfigNavEscapeClearFocusItem).
	config_nav_cursor_visible_auto:                       bool, // = true           // Using directional navigation key makes the cursor visible. Mouse click hides the cursor.
	config_nav_cursor_visible_always:                     bool, // = false          // Navigation cursor is always visible.
	config_docking_no_split:                              bool, // = false          // Simplified docking mode: disable window splitting, so docking is limited to merging multiple windows together into tab-bars.
	config_docking_with_shift:                            bool, // = false          // Enable docking with holding Shift key (reduce visual noise, allows dropping in wider space)
	config_docking_always_tab_bar:                        bool, // = false          // [BETA] [FIXME: This currently creates regression with auto-sizing and general overhead] Make every single floating window display within a docking node.
	config_docking_transparent_payload:                   bool, // = false          // [BETA] Make window or viewport transparent when docking and only display docking boxes on the target viewport. Useful if rendering of multiple viewport cannot be synced. Best used with ConfigViewportsNoAutoMerge.
	config_viewports_no_auto_merge:                       bool, // = false;         // Set to make all floating imgui windows always create their own viewport. Otherwise, they are merged into the main host viewports when overlapping it. May also set ImGuiViewportFlags_NoAutoMerge on individual viewport.
	config_viewports_no_task_bar_icon:                    bool, // = false          // Disable default OS task bar icon flag for secondary viewports. When a viewport doesn't want a task bar icon, ImGuiViewportFlags_NoTaskBarIcon will be set on it.
	config_viewports_no_decoration:                       bool, // = true           // Disable default OS window decoration flag for secondary viewports. When a viewport doesn't want window decorations, ImGuiViewportFlags_NoDecoration will be set on it. Enabling decoration can create subsequent issues at OS levels (e.g. minimum window size).
	config_viewports_no_default_parent:                   bool, // = false          // Disable default OS parenting to main viewport for secondary viewports. By default, viewports are marked with ParentViewportId = <main_viewport>, expecting the platform backend to setup a parent/child relationship between the OS windows (some backend may ignore this). Set to true if you want the default to be 0, then all viewports will be top-level OS windows.
	mouse_draw_cursor:                                    bool, // = false          // Request ImGui to draw a mouse cursor for you (if you are on a platform without a mouse cursor). Cannot be easily renamed to 'io.ConfigXXX' because this is frequently used by backend implementations.
	config_mac_osx_behaviors:                             bool, // = defined(__APPLE__) // Swap Cmd<>Ctrl keys + OS X style text editing cursor movement using Alt instead of Ctrl, Shortcuts using Cmd/Super instead of Ctrl, Line/Text Start and End using Cmd+Arrows instead of Home/End, Double click selects by word instead of selecting whole text, Multi-selection in lists uses Cmd/Super instead of Ctrl.
	config_input_trickle_event_queue:                     bool, // = true           // Enable input queue trickling: some types of events submitted during the same frame (e.g. button down + up) will be spread over multiple frames, improving interactions with low framerates.
	config_input_text_cursor_blink:                       bool, // = true           // Enable blinking cursor (optional as some users consider it to be distracting).
	config_input_text_enter_keep_active:                  bool, // = false          // [BETA] Pressing Enter will keep item active and select contents (single-line only).
	config_drag_click_to_input_text:                      bool, // = false          // [BETA] Enable turning DragXXX widgets into text input with a simple mouse click-release (without moving). Not desirable on devices without a keyboard.
	config_windows_resize_from_edges:                     bool, // = true           // Enable resizing of windows from their edges and from the lower-left corner. This requires ImGuiBackendFlags_HasMouseCursors for better mouse cursor feedback. (This used to be a per-window ImGuiWindowFlags_ResizeFromAnySide flag)
	config_windows_move_from_title_bar_only:              bool, // = false      // Enable allowing to move windows only when clicking on their title bar. Does not apply to windows without a title bar.
	config_windows_copy_contents_with_ctrl_c:             bool, // = false      // [EXPERIMENTAL] CTRL+C copy the contents of focused window into the clipboard. Experimental because: (1) has known issues with nested Begin/End pairs (2) text output quality varies (3) text output is in submission order rather than spatial order.
	config_scrollbar_scroll_by_page:                      bool, // = true           // Enable scrolling page by page when clicking outside the scrollbar grab. When disabled, always scroll to clicked location. When enabled, Shift+Click scrolls to clicked location.
	config_memory_compact_timer:                          f32, // = 60.0f          // Timer (in seconds) to free transient windows/tables memory buffers when unused. Set to -1.0f to disable.
	mouse_double_click_time:                              f32, // = 0.30f          // Time for a double-click, in seconds.
	mouse_double_click_max_dist:                          f32, // = 6.0f           // Distance threshold to stay in to validate a double-click, in pixels.
	mouse_drag_threshold:                                 f32, // = 6.0f           // Distance threshold before considering we are dragging.
	key_repeat_delay:                                     f32, // = 0.275f         // When holding a key/button, time before it starts repeating, in seconds (for buttons in Repeat mode, etc.).
	key_repeat_rate:                                      f32, // = 0.050f         // When holding a key/button, rate at which it repeats, in seconds.
	config_error_recovery:                                bool, // = true       // Enable error recovery support. Some errors won't be detected and lead to direct crashes if recovery is disabled.
	config_error_recovery_enable_assert:                  bool, // = true       // Enable asserts on recoverable error. By default call IM_ASSERT() when returning from a failing IM_ASSERT_USER_ERROR()
	config_error_recovery_enable_debug_log:               bool, // = true       // Enable debug log output on recoverable errors.
	config_error_recovery_enable_tooltip:                 bool, // = true       // Enable tooltip on recoverable errors. The tooltip include a way to enable asserts if they were disabled.
	config_debug_is_debugger_present:                     bool, // = false          // Enable various tools calling IM_DEBUG_BREAK().
	config_debug_highlight_id_conflicts:                  bool, // = true           // Highlight and show an error message popup when multiple items have conflicting identifiers.
	config_debug_highlight_id_conflicts_show_item_picker: bool, //=true // Show "Item Picker" button in aforementioned popup.
	config_debug_begin_return_value_once:                 bool, // = false          // First-time calls to Begin()/BeginChild() will return false. NEEDS TO BE SET AT APPLICATION BOOT TIME if you don't want to miss windows.
	config_debug_begin_return_value_loop:                 bool, // = false          // Some calls to Begin()/BeginChild() will return false. Will cycle through window depths then repeat. Suggested use: add "io.ConfigDebugBeginReturnValue = io.KeyShift" in your main loop then occasionally press SHIFT. Windows should be flickering while running.
	config_debug_ignore_focus_loss:                       bool, // = false          // Ignore io.AddFocusEvent(false), consequently not calling io.ClearInputKeys()/io.ClearInputMouse() in input processing.
	config_debug_ini_settings:                            bool, // = false          // Save .ini data with extra comments (particularly helpful for Docking, but makes saving slower)
	backend_platform_name:                                cstring, // = NULL
	backend_renderer_name:                                cstring, // = NULL
	backend_platform_user_data:                           rawptr, // = NULL           // User data for platform backend
	backend_renderer_user_data:                           rawptr, // = NULL           // User data for renderer backend
	backend_language_user_data:                           rawptr, // = NULL           // User data for non C++ programming language backend
	want_capture_mouse:                                   bool, // Set when Dear ImGui will use mouse inputs, in this case do not dispatch them to your main game/application (either way, always pass on mouse inputs to imgui). (e.g. unclicked mouse is hovering over an imgui window, widget is active, mouse was clicked over an imgui window, etc.).
	want_capture_keyboard:                                bool, // Set when Dear ImGui will use keyboard inputs, in this case do not dispatch them to your main game/application (either way, always pass keyboard inputs to imgui). (e.g. InputText active, or an imgui window is focused and navigation is enabled, etc.).
	want_text_input:                                      bool, // Mobile/console: when set, you may display an on-screen keyboard. This is set by Dear ImGui when it wants textual keyboard input to happen (e.g. when a InputText widget is active).
	want_set_mouse_pos:                                   bool, // MousePos has been altered, backend should reposition mouse on next frame. Rarely used! Set only when io.ConfigNavMoveSetMousePos is enabled.
	want_save_ini_settings:                               bool, // When manual .ini load/save is active (io.IniFilename == NULL), this will be set to notify your application that you can call SaveIniSettingsToMemory() and save yourself. Important: clear io.WantSaveIniSettings yourself after saving!
	nav_active:                                           bool, // Keyboard/Gamepad navigation is currently allowed (will handle ImGuiKey_NavXXX events) = a window is focused and it doesn't use the ImGuiWindowFlags_NoNavInputs flag.
	nav_visible:                                          bool, // Keyboard/Gamepad navigation highlight is visible and allowed (will handle ImGuiKey_NavXXX events).
	framerate:                                            f32, // Estimate of application framerate (rolling average over 60 frames, based on io.DeltaTime), in frame per second. Solely for convenience. Slow applications may not want to use a moving average or may want to reset underlying buffers occasionally.
	metrics_render_vertices:                              i32, // Vertices output during last call to Render()
	metrics_render_indices:                               i32, // Indices output during last call to Render() = number of triangles * 3
	metrics_render_windows:                               i32, // Number of visible windows
	metrics_active_windows:                               i32, // Number of active windows
	mouse_delta:                                          Vec2, // Mouse delta. Note that this is zero if either current or previous position are invalid (-FLT_MAX,-FLT_MAX), so a disappearing/reappearing mouse won't have a huge delta.
	ctx:                                                  ^Context, // Parent UI context (needs to be set explicitly by parent).
	mouse_pos:                                            Vec2, // Mouse position, in pixels. Set to ImVec2(-FLT_MAX, -FLT_MAX) if mouse is unavailable (on another screen, etc.)
	mouse_down:                                           [5]bool, // Mouse buttons: 0=left, 1=right, 2=middle + extras (ImGuiMouseButton_COUNT == 5). Dear ImGui mostly uses left and right buttons. Other buttons allow us to track if the mouse is being used by your application + available to user as a convenience via IsMouse** API.
	mouse_wheel:                                          f32, // Mouse wheel Vertical: 1 unit scrolls about 5 lines text. >0 scrolls Up, <0 scrolls Down. Hold SHIFT to turn vertical scroll into horizontal scroll.
	mouse_wheel_h:                                        f32, // Mouse wheel Horizontal. >0 scrolls Left, <0 scrolls Right. Most users don't have a mouse with a horizontal wheel, may not be filled by all backends.
	mouse_source:                                         Mouse_Source, // Mouse actual input peripheral (Mouse/TouchScreen/Pen).
	mouse_hovered_viewport:                               ID, // (Optional) Modify using io.AddMouseViewportEvent(). With multi-viewports: viewport the OS mouse is hovering. If possible _IGNORING_ viewports with the ImGuiViewportFlags_NoInputs flag is much better (few backends can handle that). Set io.BackendFlags |= ImGuiBackendFlags_HasMouseHoveredViewport if you can provide this info. If you don't imgui will infer the value using the rectangles and last focused time of the viewports it knows about (ignoring other OS windows).
	key_ctrl:                                             bool, // Keyboard modifier down: Control
	key_shift:                                            bool, // Keyboard modifier down: Shift
	key_alt:                                              bool, // Keyboard modifier down: Alt
	key_super:                                            bool, // Keyboard modifier down: Cmd/Super/Windows
	key_mods:                                             Key_Chord, // Key mods flags (any of ImGuiMod_Ctrl/ImGuiMod_Shift/ImGuiMod_Alt/ImGuiMod_Super flags, same as io.KeyCtrl/KeyShift/KeyAlt/KeySuper but merged into flags. Read-only, updated by NewFrame()
	keys_data:                                            [KEY_NAMED_KEY_COUNT]Key_Data, // Key state for all known keys. Use IsKeyXXX() functions to access this.
	want_capture_mouse_unless_popup_close:                bool, // Alternative to WantCaptureMouse: (WantCaptureMouse == true && WantCaptureMouseUnlessPopupClose == false) when a click over void is expected to close a popup.
	mouse_pos_prev:                                       Vec2, // Previous mouse position (note that MouseDelta is not necessary == MousePos-MousePosPrev, in case either position is invalid)
	mouse_clicked_pos:                                    [5]Vec2, // Position at time of clicking
	mouse_clicked_time:                                   [5]f64, // Time of last click (used to figure out double-click)
	mouse_clicked:                                        [5]bool, // Mouse button went from !Down to Down (same as MouseClickedCount[x] != 0)
	mouse_double_clicked:                                 [5]bool, // Has mouse button been double-clicked? (same as MouseClickedCount[x] == 2)
	mouse_clicked_count:                                  [5]u16, // == 0 (not clicked), == 1 (same as MouseClicked[]), == 2 (double-clicked), == 3 (triple-clicked) etc. when going from !Down to Down
	mouse_clicked_last_count:                             [5]u16, // Count successive number of clicks. Stays valid after mouse release. Reset after another click is done.
	mouse_released:                                       [5]bool, // Mouse button went from Down to !Down
	mouse_released_time:                                  [5]f64, // Time of last released (rarely used! but useful to handle delayed single-click when trying to disambiguate them from double-click).
	mouse_down_owned:                                     [5]bool, // Track if button was clicked inside a dear imgui window or over void blocked by a popup. We don't request mouse capture from the application if click started outside ImGui bounds.
	mouse_down_owned_unless_popup_close:                  [5]bool, // Track if button was clicked inside a dear imgui window.
	mouse_wheel_request_axis_swap:                        bool, // On a non-Mac system, holding SHIFT requests WheelY to perform the equivalent of a WheelX event. On a Mac system this is already enforced by the system.
	mouse_ctrl_left_as_right_click:                       bool, // (OSX) Set to true when the current click was a Ctrl+click that spawned a simulated right click
	mouse_down_duration:                                  [5]f32, // Duration the mouse button has been down (0.0f == just clicked)
	mouse_down_duration_prev:                             [5]f32, // Previous time the mouse button has been down
	mouse_drag_max_distance_abs:                          [5]Vec2, // Maximum distance, absolute, on each axis, of how much mouse has traveled from the clicking point
	mouse_drag_max_distance_sqr:                          [5]f32, // Squared maximum distance of how much mouse has traveled from the clicking point (used for moving thresholds)
	pen_pressure:                                         f32, // Touch/Pen pressure (0.0f to 1.0f, should be >0.0f only when MouseDown[0] == true). Helper storage currently unused by Dear ImGui.
	app_focus_lost:                                       bool, // Only modify via AddFocusEvent()
	app_accepting_events:                                 bool, // Only modify via SetAppAcceptingEvents()
	input_queue_surrogate:                                Wchar16, // For AddInputCharacterUTF16()
	input_queue_characters:                               Vector_Wchar, // Queue of _characters_ input (obtained by platform backend). Fill using AddInputCharacter() helper.
}

// Shared state of InputText(), passed as an argument to your callback when a ImGuiInputTextFlags_Callback* flag is used.
// The callback function should return 0 by default.
// Callbacks (follow a flag name and see comments in ImGuiInputTextFlags_ declarations for more details)
// - ImGuiInputTextFlags_CallbackEdit:        Callback on buffer edit. Note that InputText() already returns true on edit + you can always use IsItemEdited(). The callback is useful to manipulate the underlying buffer while focus is active.
// - ImGuiInputTextFlags_CallbackAlways:      Callback on each iteration
// - ImGuiInputTextFlags_CallbackCompletion:  Callback on pressing TAB
// - ImGuiInputTextFlags_CallbackHistory:     Callback on pressing Up/Down arrows
// - ImGuiInputTextFlags_CallbackCharFilter:  Callback on character inputs to replace or discard them. Modify 'EventChar' to replace or discard, or return 1 in callback to discard.
// - ImGuiInputTextFlags_CallbackResize:      Callback on buffer capacity changes request (beyond 'buf_size' parameter value), allowing the string to grow.
Input_Text_Callback_Data :: struct {
	ctx:             ^Context, // Parent UI context
	event_flag:      Input_Text_Flags, // One ImGuiInputTextFlags_Callback*    // Read-only
	flags:           Input_Text_Flags, // What user passed to InputText()      // Read-only
	user_data:       rawptr, // What user passed to InputText()      // Read-only
	event_char:      Wchar, // Character input                      // Read-write   // [CharFilter] Replace character with another one, or set to zero to drop. return 1 is equivalent to setting EventChar=0;
	event_key:       Key, // Key pressed (Up/Down/TAB)            // Read-only    // [Completion,History]
	buf:             cstring, // Text buffer                          // Read-write   // [Resize] Can replace pointer / [Completion,History,Always] Only write to pointed data, don't replace the actual pointer!
	buf_text_len:    i32, // Text length (in bytes)               // Read-write   // [Resize,Completion,History,Always] Exclude zero-terminator storage. In C land: == strlen(some_text), in C++ land: string.length()
	buf_size:        i32, // Buffer size (in bytes) = capacity+1  // Read-only    // [Resize,Completion,History,Always] Include zero-terminator storage. In C land == ARRAYSIZE(my_char_array), in C++ land: string.capacity()+1
	buf_dirty:       bool, // Set if you modify Buf/BufTextLen!    // Write        // [Completion,History,Always]
	cursor_pos:      i32, //                                      // Read-write   // [Completion,History,Always]
	selection_start: i32, //                                      // Read-write   // [Completion,History,Always] == to SelectionEnd when no selection)
	selection_end:   i32, //                                      // Read-write   // [Completion,History,Always]
}

// Resizing callback data to apply custom constraint. As enabled by SetNextWindowSizeConstraints(). Callback is called during the next Begin().
// NB: For basic min/max size constraint on each axis you don't need to use the callback! The SetNextWindowSizeConstraints() parameters are enough.
Size_Callback_Data :: struct {
	user_data:    rawptr, // Read-only.   What user passed to SetNextWindowSizeConstraints(). Generally store an integer or float in here (need reinterpret_cast<>).
	pos:          Vec2, // Read-only.   Window position, for reference.
	current_size: Vec2, // Read-only.   Current window size.
	desired_size: Vec2, // Read-write.  Desired size, based on user's mouse position. Write to this field to restrain resizing.
}

// [ALPHA] Rarely used / very advanced uses only. Use with SetNextWindowClass() and DockSpace() functions.
// Important: the content of this class is still highly WIP and likely to change and be refactored
// before we stabilize Docking features. Please be mindful if using this.
// Provide hints:
// - To the platform backend via altered viewport flags (enable/disable OS decoration, OS task bar icons, etc.)
// - To the platform backend for OS level parent/child relationships of viewport.
// - To the docking system for various options and filtering.
Window_Class :: struct {
	class_id:                      ID, // User data. 0 = Default class (unclassed). Windows of different classes cannot be docked with each others.
	parent_viewport_id:            ID, // Hint for the platform backend. -1: use default. 0: request platform backend to not parent the platform. != 0: request platform backend to create a parent<>child relationship between the platform windows. Not conforming backends are free to e.g. parent every viewport to the main viewport or not.
	focus_route_parent_window_id:  ID, // ID of parent window for shortcut focus route evaluation, e.g. Shortcut() call from Parent Window will succeed when this window is focused.
	viewport_flags_override_set:   Viewport_Flags, // Viewport flags to set when a window of this class owns a viewport. This allows you to enforce OS decoration or task bar icon, override the defaults on a per-window basis.
	viewport_flags_override_clear: Viewport_Flags, // Viewport flags to clear when a window of this class owns a viewport. This allows you to enforce OS decoration or task bar icon, override the defaults on a per-window basis.
	tab_item_flags_override_set:   Tab_Item_Flags, // [EXPERIMENTAL] TabItem flags to set when a window of this class gets submitted into a dock node tab bar. May use with ImGuiTabItemFlags_Leading or ImGuiTabItemFlags_Trailing.
	dock_node_flags_override_set:  Dock_Node_Flags, // [EXPERIMENTAL] Dock node flags to set when a window of this class is hosted by a dock node (it doesn't have to be selected!)
	docking_always_tab_bar:        bool, // Set to true to enforce single floating windows of this class always having their own docking node (equivalent of setting the global io.ConfigDockingAlwaysTabBar)
	docking_allow_unclassed:       bool, // Set to true to allow windows of this class to be docked/merged with an unclassed window. // FIXME-DOCK: Move to DockNodeFlags override?
}

// Data payload for Drag and Drop operations: AcceptDragDropPayload(), GetDragDropPayload()
Payload :: struct {
	data:             rawptr, // Data (copied and owned by dear imgui)
	data_size:        i32, // Data size
	source_id:        ID, // Source item id
	source_parent_id: ID, // Source parent id (if available)
	data_frame_count: i32, // Data timestamp
	data_type:        [32 + 1]cstring, // Data type tag (short user-supplied string, 32 characters max)
	preview:          bool, // Set when AcceptDragDropPayload() was called and mouse has been hovering the target item (nb: handle overlapping drag targets)
	delivery:         bool, // Set when AcceptDragDropPayload() was called and mouse button is released over the target item.
}

// [Internal]
Text_Filter_Gui_Text_Range :: struct {
	b: cstring,
	e: cstring,
}

// Helper: Parse and apply text filters. In format "aaaaa[,bbbb][,ccccc]"
Text_Filter :: struct {
	input_buf:  [256]cstring,
	filters:    Vector_Gui_Text_Filter_Gui_Text_Range,
	count_grep: i32,
}

// Helper: Growable text buffer for logging/accumulating text
// (this could be called 'ImGuiTextBuilder' / 'ImGuiStringBuilder')
Text_Buffer :: struct {
	buf: Vector_char,
}

// [Internal] Key+Value for ImGuiStorage
Storage_Pair :: struct {
	key:              ID,
	_anonymous_type0: __anonymous_type0,
}

__anonymous_type0 :: struct {
	val_i: i32,
	val_f: f32,
	val_p: rawptr,
}

// Helper: Key->Value storage
// Typically you don't have to worry about this since a storage is held within each Window.
// We use it to e.g. store collapse state for a tree (Int 0/1)
// This is optimized for efficient lookup (dichotomy into a contiguous buffer) and rare insertion (typically tied to user interactions aka max once a frame)
// You can use it as custom user storage for temporary values. Declare your own storage if, for example:
// - You want to manipulate the open/close state of a particular sub-tree in your interface (tree node uses Int 0/1 to store their state).
// - You want to store custom debug data easily without adding or editing structures in your code (probably not efficient, but convenient)
// Types are NOT stored, so it is up to you to make sure your Key don't collide with different types.
Storage :: struct {
	data: Vector_Gui_Storage_Pair,
}

// Helper: Manually clip large list of items.
// If you have lots evenly spaced items and you have random access to the list, you can perform coarse
// clipping based on visibility to only submit items that are in view.
// The clipper calculates the range of visible items and advance the cursor to compensate for the non-visible items we have skipped.
// (Dear ImGui already clip items based on their bounds but: it needs to first layout the item to do so, and generally
//  fetching/submitting your own data incurs additional cost. Coarse clipping using ImGuiListClipper allows you to easily
//  scale using lists with tens of thousands of items without a problem)
// Usage:
//   ImGuiListClipper clipper;
//   clipper.Begin(1000);         // We have 1000 elements, evenly spaced.
//   while (clipper.Step())
//       for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++)
//           ImGui::Text("line number %d", i);
// Generally what happens is:
// - Clipper lets you process the first element (DisplayStart = 0, DisplayEnd = 1) regardless of it being visible or not.
// - User code submit that one element.
// - Clipper can measure the height of the first element
// - Clipper calculate the actual range of elements to display based on the current clipping rectangle, position the cursor before the first visible element.
// - User code submit visible elements.
// - The clipper also handles various subtleties related to keyboard/gamepad navigation, wrapping etc.
List_Clipper :: struct {
	ctx:                 ^Context, // Parent UI context
	display_start:       i32, // First item to display, updated by each call to Step()
	display_end:         i32, // End of items to display (exclusive)
	items_count:         i32, // [Internal] Number of items
	items_height:        f32, // [Internal] Height of item after a first step and item submission can calculate it
	start_pos_y:         f32, // [Internal] Cursor position at the time of Begin() or after table frozen rows are all processed
	start_seek_offset_y: f64, // [Internal] Account for frozen rows in a table and initial loss of precision in very large windows.
	temp_data:           rawptr, // [Internal] Internal data
}

// Helper: ImColor() implicitly converts colors to either ImU32 (packed 4x1 byte) or ImVec4 (4x1 float)
// Prefer using IM_COL32() macros if you want a guaranteed compile-time ImU32 for usage with ImDrawList API.
// **Avoid storing ImColor! Store either u32 of ImVec4. This is not a full-featured color class. MAY OBSOLETE.
// **None of the ImGui API are using ImColor directly but you can use it as a convenience to pass colors in either ImU32 or ImVec4 formats. Explicitly cast to ImU32 or ImVec4 if needed.
Color :: struct {
	value: Vec4,
}

// Main IO structure returned by BeginMultiSelect()/EndMultiSelect().
// This mainly contains a list of selection requests.
// - Use 'Demo->Tools->Debug Log->Selection' to see requests as they happen.
// - Some fields are only useful if your list is dynamic and allows deletion (getting post-deletion focus/state right is shown in the demo)
// - Below: who reads/writes each fields? 'r'=read, 'w'=write, 'ms'=multi-select code, 'app'=application/user code.
Multi_Select_IO :: struct {
	requests:        Vector_Gui_Selection_Request, //  ms:w, app:r     /  ms:w  app:r   // Requests to apply to your selection data.
	range_src_item:  Selection_User_Data, //  ms:w  app:r     /                // (If using clipper) Begin: Source item (often the first selected item) must never be clipped: use clipper.IncludeItemByIndex() to ensure it is submitted.
	nav_id_item:     Selection_User_Data, //  ms:w, app:r     /                // (If using deletion) Last known SetNextItemSelectionUserData() value for NavId (if part of submitted items).
	nav_id_selected: bool, //  ms:w, app:r     /        app:r   // (If using deletion) Last known selection state for NavId (if part of submitted items).
	range_src_reset: bool, //        app:w     /  ms:r          // (If using deletion) Set before EndMultiSelect() to reset ResetSrcItem (e.g. if deleted selection).
	items_count:     i32, //  ms:w, app:r     /        app:r   // 'int items_count' parameter to BeginMultiSelect() is copied here for convenience, allowing simpler calls to your ApplyRequests handler. Not used internally.
}

// Selection request item
Selection_Request :: struct {
	type:             Selection_Request_Type, //  ms:w, app:r     /  ms:w, app:r   // Request type. You'll most often receive 1 Clear + 1 SetRange with a single-item range.
	selected:         bool, //  ms:w, app:r     /  ms:w, app:r   // Parameter for SetAll/SetRange requests (true = select, false = unselect)
	range_direction:  i8, //                  /  ms:w  app:r   // Parameter for SetRange request: +1 when RangeFirstItem comes before RangeLastItem, -1 otherwise. Useful if you want to preserve selection order on a backward Shift+Click.
	range_first_item: Selection_User_Data, //                  /  ms:w, app:r   // Parameter for SetRange request (this is generally == RangeSrcItem when shift selecting from top to bottom).
	range_last_item:  Selection_User_Data, //                  /  ms:w, app:r   // Parameter for SetRange request (this is generally == RangeSrcItem when shift selecting from bottom to top). Inclusive!
}

// Optional helper to store multi-selection state + apply multi-selection requests.
// - Used by our demos and provided as a convenience to easily implement basic multi-selection.
// - Iterate selection with 'void* it = NULL; ImGuiID id; while (selection.GetNextSelectedItem(&it, &id)) { ... }'
//   Or you can check 'if (Contains(id)) { ... }' for each possible object if their number is not too high to iterate.
// - USING THIS IS NOT MANDATORY. This is only a helper and not a required API.
// To store a multi-selection, in your application you could:
// - Use this helper as a convenience. We use our simple key->value ImGuiStorage as a std::set<ImGuiID> replacement.
// - Use your own external storage: e.g. std::set<MyObjectId>, std::vector<MyObjectId>, interval trees, intrusively stored selection etc.
// In ImGuiSelectionBasicStorage we:
// - always use indices in the multi-selection API (passed to SetNextItemSelectionUserData(), retrieved in ImGuiMultiSelectIO)
// - use the AdapterIndexToStorageId() indirection layer to abstract how persistent selection data is derived from an index.
// - use decently optimized logic to allow queries and insertion of very large selection sets.
// - do not preserve selection order.
// Many combinations are possible depending on how you prefer to store your items and how you prefer to store your selection.
// Large applications are likely to eventually want to get rid of this indirection layer and do their own thing.
// See https://github.com/ocornut/imgui/wiki/Multi-Select for details and pseudo-code using this helper.
Selection_Basic_Storage :: struct {
	size:                        i32, //          // Number of selected items, maintained by this helper.
	preserve_order:              bool, // = false  // GetNextSelectedItem() will return ordered selection (currently implemented by two additional sorts of selection. Could be improved)
	user_data:                   rawptr, // = NULL   // User data for use by adapter function        // e.g. selection.UserData = (void*)my_items;
	adapter_index_to_storage_id: proc "c" (self: ^Selection_Basic_Storage, idx: i32) -> ID,
	_selection_order:            i32, // [Internal] Increasing counter to store selection order
	_storage:                    Storage, // [Internal] Selection set. Think of this as similar to e.g. std::set<ImGuiID>. Prefer not accessing directly: iterate with GetNextSelectedItem().
}

// Optional helper to apply multi-selection requests to existing randomly accessible storage.
// Convenient if you want to quickly wire multi-select API on e.g. an array of bool or items storing their own selection state.
Selection_External_Storage :: struct {
	user_data:                 rawptr, // User data for use by adapter function                                // e.g. selection.UserData = (void*)my_items;
	adapter_set_item_selected: proc "c" (
		self: ^Selection_External_Storage,
		idx: i32,
		selected: bool,
	),
}

// Typically, 1 command = 1 GPU draw call (unless command is a callback)
// - VtxOffset: When 'io.BackendFlags & ImGuiBackendFlags_RendererHasVtxOffset' is enabled,
//   this fields allow us to render meshes larger than 64K vertices while keeping 16-bit indices.
//   Backends made for <1.71. will typically ignore the VtxOffset fields.
// - The ClipRect/TextureId/VtxOffset fields must be contiguous as we memcmp() them together (this is asserted for).
Draw_Cmd :: struct {
	clip_rect:                 Vec4, // 4*4  // Clipping rectangle (x1, y1, x2, y2). Subtract ImDrawData->DisplayPos to get clipping rectangle in "viewport" coordinates
	texture_id:                Texture_ID, // 4-8  // User-provided texture ID. Set by user in ImfontAtlas::SetTexID() for fonts or passed to Image*() functions. Ignore if never using images or multiple fonts atlas.
	vtx_offset:                u32, // 4    // Start offset in vertex buffer. ImGuiBackendFlags_RendererHasVtxOffset: always 0, otherwise may be >0 to support meshes larger than 64K vertices with 16-bit indices.
	idx_offset:                u32, // 4    // Start offset in index buffer.
	elem_count:                u32, // 4    // Number of indices (multiple of 3) to be rendered as triangles. Vertices are stored in the callee ImDrawList's vtx_buffer[] array, indices in idx_buffer[].
	user_callback:             Draw_Callback, // 4-8  // If != NULL, call the function instead of rendering the vertices. clip_rect and texture_id will be set normally.
	user_callback_data:        rawptr, // 4-8  // Callback user data (when UserCallback != NULL). If called AddCallback() with size == 0, this is a copy of the AddCallback() argument. If called AddCallback() with size > 0, this is pointing to a buffer where data is stored.
	user_callback_data_size:   i32, // 4 // Size of callback user data when using storage, otherwise 0.
	user_callback_data_offset: i32, // 4 // [Internal] Offset of callback user data when using storage, otherwise -1.
}

Draw_Vert :: struct {
	pos: Vec2,
	uv:  Vec2,
	col: u32,
}

// [Internal] For use by ImDrawList
Draw_Cmd_Header :: struct {
	clip_rect:  Vec4,
	texture_id: Texture_ID,
	vtx_offset: u32,
}

// [Internal] For use by ImDrawListSplitter
Draw_Channel :: struct {
	_cmd_buffer: Vector_Draw_Cmd,
	_idx_buffer: Vector_Draw_Idx,
}

// Split/Merge functions are used to split the draw list into different layers which can be drawn into out of order.
// This is used by the Columns/Tables API, so items of each column can be batched together in a same draw call.
Draw_List_Splitter :: struct {
	_current:  i32, // Current channel number (0)
	_count:    i32, // Number of active channels (1+)
	_channels: Vector_Draw_Channel, // Draw channels (not resized down so _Count might be < Channels.Size)
}

// Draw command list
// This is the low-level list of polygons that ImGui:: functions are filling. At the end of the frame,
// all command lists are passed to your ImGuiIO::RenderDrawListFn function for rendering.
// Each dear imgui window contains its own ImDrawList. You can use ImGui::GetWindowDrawList() to
// access the current window draw list and draw custom primitives.
// You can interleave normal ImGui:: calls and adding primitives to the current draw list.
// In single viewport mode, top-left is == GetMainViewport()->Pos (generally 0,0), bottom-right is == GetMainViewport()->Pos+Size (generally io.DisplaySize).
// You are totally free to apply whatever transformation matrix you want to the data (depending on the use of the transformation you may want to apply it to ClipRect as well!)
// Important: Primitives are always added to the list and not culled (culling is done at higher-level by ImGui:: functions), if you use this API a lot consider coarse culling your drawn objects.
Draw_List :: struct {
	cmd_buffer:          Vector_Draw_Cmd, // Draw commands. Typically 1 command = 1 GPU draw call, unless the command is a callback.
	idx_buffer:          Vector_Draw_Idx, // Index buffer. Each command consume ImDrawCmd::ElemCount of those
	vtx_buffer:          Vector_Draw_Vert, // Vertex buffer.
	flags:               Draw_List_Flags, // Flags, you may poke into these to adjust anti-aliasing settings per-primitive.
	_vtx_current_idx:    u32, // [Internal] generally == VtxBuffer.Size unless we are past 64K vertices, in which case this gets reset to 0.
	_data:               ^Draw_List_Shared_Data, // Pointer to shared draw data (you can use ImGui::GetDrawListSharedData() to get the one from current ImGui context)
	_vtx_write_ptr:      ^Draw_Vert, // [Internal] point within VtxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
	_idx_write_ptr:      ^Draw_Idx, // [Internal] point within IdxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
	_path:               Vector_Vec2, // [Internal] current path building
	_cmd_header:         Draw_Cmd_Header, // [Internal] template of active commands. Fields should match those of CmdBuffer.back().
	_splitter:           Draw_List_Splitter, // [Internal] for channels api (note: prefer using your own persistent instance of ImDrawListSplitter!)
	_clip_rect_stack:    Vector_Vec4, // [Internal]
	_texture_id_stack:   Vector_Texture_ID, // [Internal]
	_callbacks_data_buf: Vector_U8, // [Internal]
	_fringe_scale:       f32, // [Internal] anti-alias fringe is scaled by this value, this helps to keep things sharp while zooming at vertex buffer content
	_owner_name:         cstring, // Pointer to owner window's name for debugging
}

// All draw data to render a Dear ImGui frame
// (NB: the style and the naming convention here is a little inconsistent, we currently preserve them for backward compatibility purpose,
// as this is one of the oldest structure exposed by the library! Basically, ImDrawList == CmdList)
Draw_Data :: struct {
	valid:             bool, // Only valid after Render() is called and before the next NewFrame() is called.
	cmd_lists_count:   i32, // Number of ImDrawList* to render
	total_idx_count:   i32, // For convenience, sum of all ImDrawList's IdxBuffer.Size
	total_vtx_count:   i32, // For convenience, sum of all ImDrawList's VtxBuffer.Size
	cmd_lists:         Vector_Draw_List_Ptr, // Array of ImDrawList* to render. The ImDrawLists are owned by ImGuiContext and only pointed to from here.
	display_pos:       Vec2, // Top-left position of the viewport to render (== top-left of the orthogonal projection matrix to use) (== GetMainViewport()->Pos for the main viewport, == (0.0) in most single-viewport applications)
	display_size:      Vec2, // Size of the viewport to render (== GetMainViewport()->Size for the main viewport, == io.DisplaySize in most single-viewport applications)
	framebuffer_scale: Vec2, // Amount of pixels for each unit of DisplaySize. Based on io.DisplayFramebufferScale. Generally (1,1) on normal display, (2,2) on OSX with Retina display.
	owner_viewport:    ^Viewport, // Viewport carrying the ImDrawData instance, might be of use to the renderer (generally not).
}

// A font input/source (we may rename this to ImFontSource in the future)
Font_Config :: struct {
	font_data:                rawptr, //          // TTF/OTF data
	font_data_size:           i32, //          // TTF/OTF data size
	font_data_owned_by_atlas: bool, // true     // TTF/OTF data ownership taken by the container ImFontAtlas (will delete memory itself).
	merge_mode:               bool, // false    // Merge into previous ImFont, so you can combine multiple inputs font into one ImFont (e.g. ASCII font + icons + Japanese glyphs). You may want to use GlyphOffset.y when merge font of different heights.
	pixel_snap_h:             bool, // false    // Align every glyph AdvanceX to pixel boundaries. Useful e.g. if you are merging a non-pixel aligned font with the default font. If enabled, you can set OversampleH/V to 1.
	font_no:                  i32, // 0        // Index of font within TTF/OTF file
	oversample_h:             i32, // 0 (2)    // Rasterize at higher quality for sub-pixel positioning. 0 == auto == 1 or 2 depending on size. Note the difference between 2 and 3 is minimal. You can reduce this to 1 for large glyphs save memory. Read https://github.com/nothings/stb/blob/master/tests/oversample/README.md for details.
	oversample_v:             i32, // 0 (1)    // Rasterize at higher quality for sub-pixel positioning. 0 == auto == 1. This is not really useful as we don't use sub-pixel positions on the Y axis.
	size_pixels:              f32, //          // Size in pixels for rasterizer (more or less maps to the resulting font height).
	glyph_offset:             Vec2, // 0, 0     // Offset all glyphs from this font input.
	glyph_ranges:             ^Wchar, // NULL     // THE ARRAY DATA NEEDS TO PERSIST AS LONG AS THE FONT IS ALIVE. Pointer to a user-provided list of Unicode range (2 value per range, values are inclusive, zero-terminated list).
	glyph_min_advance_x:      f32, // 0        // Minimum AdvanceX for glyphs, set Min to align font icons, set both Min/Max to enforce mono-space font
	glyph_max_advance_x:      f32, // FLT_MAX  // Maximum AdvanceX for glyphs
	glyph_extra_advance_x:    f32, // 0        // Extra spacing (in pixels) between glyphs. Please contact us if you are using this.
	font_builder_flags:       u32, // 0        // Settings for custom font builder. THIS IS BUILDER IMPLEMENTATION DEPENDENT. Leave as zero if unsure.
	rasterizer_multiply:      f32, // 1.0f     // Linearly brighten (>1.0f) or darken (<1.0f) font output. Brightening small fonts may be a good workaround to make them more readable. This is a silly thing we may remove in the future.
	rasterizer_density:       f32, // 1.0f     // DPI scale for rasterization, not altering other font metrics: make it easy to swap between e.g. a 100% and a 400% fonts for a zooming display. IMPORTANT: If you increase this it is expected that you increase font scale accordingly, otherwise quality may look lowered.
	ellipsis_char:            Wchar, // 0        // Explicitly specify Unicode codepoint of ellipsis character. When fonts are being merged first specified ellipsis will be used.
	name:                     [40]cstring, // Name (strictly to ease debugging)
	dst_font:                 ^Font,
}

// Hold rendering data for one glyph.
// (Note: some language parsers may fail to convert the 31+1 bitfield members, in this case maybe drop store a single u32 or we can rework this)
Font_Glyph :: struct {
	colored:   u32, // Flag to indicate glyph is colored and should generally ignore tinting (make it usable with no shift on little-endian as this is used in loops)
	visible:   u32, // Flag to indicate glyph has no visible pixels (e.g. space). Allow early out when rendering.
	codepoint: u32, // 0x0000..0x10FFFF
	advance_x: f32, // Horizontal distance to advance layout with
	x0:        f32, // Glyph corners
	y0:        f32, // Glyph corners
	x1:        f32, // Glyph corners
	y1:        f32, // Glyph corners
	u0:        f32, // Texture coordinates
	v0:        f32, // Texture coordinates
	u1:        f32, // Texture coordinates
	v1:        f32, // Texture coordinates
}

// Helper to build glyph ranges from text/string data. Feed your application strings/characters to it then call BuildRanges().
// This is essentially a tightly packed of vector of 64k booleans = 8KB storage.
Font_Glyph_Ranges_Builder :: struct {
	used_chars: Vector_U32, // Store 1-bit per Unicode code point (0=unused, 1=used)
}

// See ImFontAtlas::AddCustomRectXXX functions.
Font_Atlas_Custom_Rect :: struct {
	x:               u16, // Output   // Packed position in Atlas
	y:               u16, // Output   // Packed position in Atlas
	width:           u16, // Input    // Desired rectangle dimension
	height:          u16, // Input    // Desired rectangle dimension
	glyph_id:        u32, // Input    // For custom font glyphs only (ID < 0x110000)
	glyph_colored:   u32, // Input  // For custom font glyphs only: glyph is colored, removed tinting.
	glyph_advance_x: f32, // Input    // For custom font glyphs only: glyph xadvance
	glyph_offset:    Vec2, // Input    // For custom font glyphs only: glyph display offset
	font:            ^Font, // Input    // For custom font glyphs only: target font
}

// Load and rasterize multiple TTF/OTF fonts into a same texture. The font atlas will build a single texture holding:
//  - One or more fonts.
//  - Custom graphics data needed to render the shapes needed by Dear ImGui.
//  - Mouse cursor shapes for software cursor rendering (unless setting 'Flags |= ImFontAtlasFlags_NoMouseCursors' in the font atlas).
// It is the user-code responsibility to setup/build the atlas, then upload the pixel data into a texture accessible by your graphics api.
//  - Optionally, call any of the AddFont*** functions. If you don't call any, the default font embedded in the code will be loaded for you.
//  - Call GetTexDataAsAlpha8() or GetTexDataAsRGBA32() to build and retrieve pixels data.
//  - Upload the pixels data into a texture within your graphics system (see imgui_impl_xxxx.cpp examples)
//  - Call SetTexID(my_tex_id); and pass the pointer/identifier to your texture in a format natural to your graphics API.
//    This value will be passed back to you during rendering to identify the texture. Read FAQ entry about ImTextureID for more details.
// Common pitfalls:
// - If you pass a 'glyph_ranges' array to AddFont*** functions, you need to make sure that your array persist up until the
//   atlas is build (when calling GetTexData*** or Build()). We only copy the pointer, not the data.
// - Important: By default, AddFontFromMemoryTTF() takes ownership of the data. Even though we are not writing to it, we will free the pointer on destruction.
//   You can set font_cfg->FontDataOwnedByAtlas=false to keep ownership of your data and it won't be freed,
// - Even though many functions are suffixed with "TTF", OTF data is supported just as well.
// - This is an old API and it is currently awkward for those and various other reasons! We will address them in the future!
Font_Atlas :: struct {
	flags:                 Font_Atlas_Flags, // Build flags (see ImFontAtlasFlags_)
	tex_id:                Texture_ID, // User data to refer to the texture once it has been uploaded to user's graphic systems. It is passed back to you during rendering via the ImDrawCmd structure.
	tex_desired_width:     i32, // Texture width desired by user before Build(). Must be a power-of-two. If have many glyphs your graphics API have texture size restrictions you may want to increase texture width to decrease height.
	tex_glyph_padding:     i32, // FIXME: Should be called "TexPackPadding". Padding between glyphs within texture in pixels. Defaults to 1. If your rendering method doesn't rely on bilinear filtering you may set this to 0 (will also need to set AntiAliasedLinesUseTex = false).
	user_data:             rawptr, // Store your own atlas related user-data (if e.g. you have multiple font atlas).
	locked:                bool, // Marked as Locked by ImGui::NewFrame() so attempt to modify the atlas will assert.
	tex_ready:             bool, // Set when texture was built matching current font input
	tex_pixels_use_colors: bool, // Tell whether our texture data is known to use colors (rather than just alpha channel), in order to help backend select a format.
	tex_pixels_alpha8:     ^u8, // 1 component per pixel, each component is unsigned 8-bit. Total size = TexWidth * TexHeight
	tex_pixels_rgba32:     ^u32, // 4 component per pixel, each component is unsigned 8-bit. Total size = TexWidth * TexHeight * 4
	tex_width:             i32, // Texture width calculated during Build().
	tex_height:            i32, // Texture height calculated during Build().
	tex_uv_scale:          Vec2, // = (1.0f/TexWidth, 1.0f/TexHeight)
	tex_uv_white_pixel:    Vec2, // Texture coordinates to a white pixel
	fonts:                 Vector_Font_Ptr, // Hold all the fonts returned by AddFont*. Fonts[0] is the default font upon calling ImGui::NewFrame(), use ImGui::PushFont()/PopFont() to change the current font.
	custom_rects:          Vector_Font_Atlas_Custom_Rect, // Rectangles for packing custom texture data into the atlas.
	sources:               Vector_Font_Config, // Source/configuration data
	tex_uv_lines:          [DRAWLIST_TEX_LINES_WIDTH_MAX + 1]Vec4, // UVs for baked anti-aliased lines
	font_builder_io:       ^Font_Builder_IO, // Opaque interface to a font builder (default to stb_truetype, can be changed to use FreeType by defining IMGUI_ENABLE_FREETYPE).
	font_builder_flags:    u32, // Shared flags (for all fonts) for custom font builder. THIS IS BUILD IMPLEMENTATION DEPENDENT. Per-font override is also available in ImFontConfig.
	pack_id_mouse_cursors: i32, // Custom texture rectangle ID for white pixel and mouse cursors
	pack_id_lines:         i32, // Custom texture rectangle ID for baked anti-aliased lines
}

// Font runtime data and rendering
// ImFontAtlas automatically loads a default embedded font for you when you call GetTexDataAsAlpha8() or GetTexDataAsRGBA32().
Font :: struct {
	index_advance_x:       Vector_float, // 12-16 // out // Sparse. Glyphs->AdvanceX in a directly indexable way (cache-friendly for CalcTextSize functions which only this info, and are often bottleneck in large UI).
	fallback_advance_x:    f32, // 4     // out // = FallbackGlyph->AdvanceX
	font_size:             f32, // 4     // in  // Height of characters/line, set during loading (don't change after loading)
	index_lookup:          Vector_U16, // 12-16 // out // Sparse. Index glyphs by Unicode code-point.
	glyphs:                Vector_Font_Glyph, // 12-16 // out // All glyphs.
	fallback_glyph:        ^Font_Glyph, // 4-8   // out // = FindGlyph(FontFallbackChar)
	container_atlas:       ^Font_Atlas, // 4-8   // out // What we has been loaded into
	sources:               ^Font_Config, // 4-8   // in  // Pointer within ContainerAtlas->Sources[], to SourcesCount instances
	sources_count:         i16, // 2     // in  // Number of ImFontConfig involved in creating this font. Usually 1, or >1 when merging multiple font sources into one ImFont.
	ellipsis_char_count:   i16, // 1     // out // 1 or 3
	ellipsis_char:         Wchar, // 2-4   // out // Character used for ellipsis rendering ('...').
	fallback_char:         Wchar, // 2-4   // out // Character used if a glyph isn't found (U+FFFD, '?')
	ellipsis_width:        f32, // 4     // out // Total ellipsis Width
	ellipsis_char_step:    f32, // 4     // out // Step between characters when EllipsisCount > 0
	scale:                 f32, // 4     // in  // Base font scale (1.0f), multiplied by the per-window font scale which you can adjust with SetWindowFontScale()
	ascent:                f32, // 4+4   // out // Ascent: distance from top to bottom of e.g. 'A' [0..FontSize] (unscaled)
	descent:               f32, // 4+4   // out // Ascent: distance from top to bottom of e.g. 'A' [0..FontSize] (unscaled)
	metrics_total_surface: i32, // 4     // out // Total surface in pixels to get an idea of the font rasterization/texture cost (not exact, we approximate the cost of padding between glyphs)
	dirty_lookup_tables:   bool, // 1     // out //
	used8k_pages_map:      [(UNICODE_CODEPOINT_MAX + 1) / 8192 / 8]u8, // 1 bytes if ImWchar=ImWchar16, 16 bytes if ImWchar==ImWchar32. Store 1-bit for each block of 4K codepoints that has one active glyph. This is mainly used to facilitate iterations across all used codepoints.
}

// - Currently represents the Platform Window created by the application which is hosting our Dear ImGui windows.
// - With multi-viewport enabled, we extend this concept to have multiple active viewports.
// - In the future we will extend this concept further to also represent Platform Monitor and support a "no main platform window" operation mode.
// - About Main Area vs Work Area:
//   - Main Area = entire viewport.
//   - Work Area = entire viewport minus sections used by main menu bars (for platform windows), or by task bar (for platform monitor).
//   - Windows are generally trying to stay within the Work Area of their host viewport.
Viewport :: struct {
	id:                      ID, // Unique identifier for the viewport
	flags:                   Viewport_Flags, // See ImGuiViewportFlags_
	pos:                     Vec2, // Main Area: Position of the viewport (Dear ImGui coordinates are the same as OS desktop/native coordinates)
	size:                    Vec2, // Main Area: Size of the viewport.
	work_pos:                Vec2, // Work Area: Position of the viewport minus task bars, menus bars, status bars (>= Pos)
	work_size:               Vec2, // Work Area: Size of the viewport minus task bars, menu bars, status bars (<= Size)
	dpi_scale:               f32, // 1.0f = 96 DPI = No extra scale.
	parent_viewport_id:      ID, // (Advanced) 0: no parent. Instruct the platform backend to setup a parent/child relationship between platform windows.
	draw_data:               ^Draw_Data, // The ImDrawData corresponding to this viewport. Valid after Render() and until the next call to NewFrame().
	renderer_user_data:      rawptr, // void* to hold custom data structure for the renderer (e.g. swap chain, framebuffers etc.). generally set by your Renderer_CreateWindow function.
	platform_user_data:      rawptr, // void* to hold custom data structure for the OS / platform (e.g. windowing info, render context). generally set by your Platform_CreateWindow function.
	platform_handle:         rawptr, // void* to hold higher-level, platform window handle (e.g. HWND for Win32 backend, Uint32 WindowID for SDL, GLFWWindow* for GLFW), for FindViewportByPlatformHandle().
	platform_handle_raw:     rawptr, // void* to hold lower-level, platform-native window handle (always HWND on Win32 platform, unused for other platforms).
	platform_window_created: bool, // Platform window has been created (Platform_CreateWindow() has been called). This is false during the first frame where a viewport is being created.
	platform_request_move:   bool, // Platform window requested move (e.g. window was moved by the OS / host window manager, authoritative position will be OS window position)
	platform_request_resize: bool, // Platform window requested resize (e.g. window was resized by the OS / host window manager, authoritative size will be OS window size)
	platform_request_close:  bool, // Platform window requested closure (e.g. window was moved by the OS / host window manager, e.g. pressing ALT-F4)
}

// Access via ImGui::GetPlatformIO()
Platform_IO :: struct {
	platform_get_clipboard_text_fn:       proc "c" (ctx: ^Context) -> cstring,
	platform_set_clipboard_text_fn:       proc "c" (ctx: ^Context, text: cstring),
	platform_clipboard_user_data:         rawptr,
	platform_open_in_shell_fn:            proc "c" (ctx: ^Context, path: cstring) -> bool,
	platform_open_in_shell_user_data:     rawptr,
	platform_set_ime_data_fn:             proc "c" (
		ctx: ^Context,
		viewport: ^Viewport,
		data: ^Platforme_Data,
	),
	platform_ime_user_data:               rawptr,
	platform_locale_decimal_point:        Wchar, // '.'
	renderer_render_state:                rawptr,
	platform_create_window:               proc "c" (vp: ^Viewport),
	platform_destroy_window:              proc "c" (vp: ^Viewport),
	platform_show_window:                 proc "c" (vp: ^Viewport),
	platform_set_window_pos:              proc "c" (vp: ^Viewport, pos: Vec2),
	platform_get_window_pos:              proc "c" (vp: ^Viewport) -> Vec2,
	platform_set_window_size:             proc "c" (vp: ^Viewport, size: Vec2),
	platform_get_window_size:             proc "c" (vp: ^Viewport) -> Vec2,
	platform_set_window_focus:            proc "c" (vp: ^Viewport),
	platform_get_window_focus:            proc "c" (vp: ^Viewport) -> bool,
	platform_get_window_minimized:        proc "c" (vp: ^Viewport) -> bool,
	platform_set_window_title:            proc "c" (vp: ^Viewport, str: cstring),
	platform_set_window_alpha:            proc "c" (vp: ^Viewport, alpha: f32),
	platform_update_window:               proc "c" (vp: ^Viewport),
	platform_render_window:               proc "c" (vp: ^Viewport, render_arg: rawptr),
	platform_swap_buffers:                proc "c" (vp: ^Viewport, render_arg: rawptr),
	platform_get_window_dpi_scale:        proc "c" (vp: ^Viewport) -> f32,
	platform_on_changed_viewport:         proc "c" (vp: ^Viewport),
	platform_get_window_work_area_insets: proc "c" (vp: ^Viewport) -> Vec4,
	platform_create_vk_surface:           proc "c" (
		vp: ^Viewport,
		vk_inst: u64,
		vk_allocators: rawptr,
		out_vk_surface: ^u64,
	) -> i32,
	renderer_create_window:               proc "c" (vp: ^Viewport),
	renderer_destroy_window:              proc "c" (vp: ^Viewport),
	renderer_set_window_size:             proc "c" (vp: ^Viewport, size: Vec2),
	renderer_render_window:               proc "c" (vp: ^Viewport, render_arg: rawptr),
	renderer_swap_buffers:                proc "c" (vp: ^Viewport, render_arg: rawptr),
	monitors:                             Vector_Gui_Platform_Monitor,
	viewports:                            Vector_Gui_Viewport_Ptr, // Main viewports, followed by all secondary viewports.
}

// (Optional) This is required when enabling multi-viewport. Represent the bounds of each connected monitor/display and their DPI.
// We use this information for multiple DPI support + clamping the position of popups and tooltips so they don't straddle multiple monitors.
Platform_Monitor :: struct {
	main_pos:        Vec2, // Coordinates of the area displayed on this monitor (Min = upper left, Max = bottom right)
	main_size:       Vec2, // Coordinates of the area displayed on this monitor (Min = upper left, Max = bottom right)
	work_pos:        Vec2, // Coordinates without task bars / side bars / menu bars. Used to avoid positioning popups/tooltips inside this region. If you don't have this info, please copy the value for MainPos/MainSize.
	work_size:       Vec2, // Coordinates without task bars / side bars / menu bars. Used to avoid positioning popups/tooltips inside this region. If you don't have this info, please copy the value for MainPos/MainSize.
	dpi_scale:       f32, // 1.0f = 96 DPI
	platform_handle: rawptr, // Backend dependant data (e.g. HMONITOR, GLFWmonitor*, SDL Display Index, NSScreen*)
}

// (Optional) Support for IME (Input Method Editor) via the platform_io.Platform_SetImeDataFn() function.
Platforme_Data :: struct {
	want_visible:      bool, // A widget wants the IME to be visible
	input_pos:         Vec2, // Position of the input cursor
	input_line_height: f32, // Line height
}

@(default_calling_convention = "c")
foreign lib {
	// Context creation and access
	// - Each context create its own ImFontAtlas by default. You may instance one yourself and pass it to CreateContext() to share a font atlas between contexts.
	// - DLL users: heaps and globals are not shared across DLL boundaries! You will need to call SetCurrentContext() + SetAllocatorFunctions()
	//   for each static/DLL boundary you are calling from. Read "Context and Memory Allocators" section of imgui.cpp for details.
	@(link_name = "ImGui_CreateContext")
	create_context :: proc(shared_font_atlas: ^Font_Atlas = nil) -> ^Context ---
	// NULL = destroy current context
	@(link_name = "ImGui_DestroyContext")
	destroy_context :: proc(ctx: ^Context = nil) ---
	@(link_name = "ImGui_GetCurrentContext")
	get_current_context :: proc() -> ^Context ---
	@(link_name = "ImGui_SetCurrentContext")
	set_current_context :: proc(ctx: ^Context) ---
	// Main
	// access the ImGuiIO structure (mouse/keyboard/gamepad inputs, time, various configuration options/flags)
	@(link_name = "ImGui_GetIO")
	get_io :: proc() -> ^IO ---
	// access the ImGuiPlatformIO structure (mostly hooks/functions to connect to platform/renderer and OS Clipboard, IME etc.)
	@(link_name = "ImGui_GetPlatformIO")
	get_platform_io :: proc() -> ^Platform_IO ---
	// access the Style structure (colors, sizes). Always use PushStyleColor(), PushStyleVar() to modify style mid-frame!
	@(link_name = "ImGui_GetStyle")
	get_style :: proc() -> ^Style ---
	// start a new Dear ImGui frame, you can submit any command from this point until Render()/EndFrame().
	@(link_name = "ImGui_NewFrame")
	new_frame :: proc() ---
	// ends the Dear ImGui frame. automatically called by Render(). If you don't need to render data (skipping rendering) you may call EndFrame() without Render()... but you'll have wasted CPU already! If you don't need to render, better to not create any windows and not call NewFrame() at all!
	@(link_name = "ImGui_EndFrame")
	end_frame :: proc() ---
	// ends the Dear ImGui frame, finalize the draw data. You can then get call GetDrawData().
	@(link_name = "ImGui_Render")
	render :: proc() ---
	// valid after Render() and until the next call to NewFrame(). this is what you have to render.
	@(link_name = "ImGui_GetDrawData")
	get_draw_data :: proc() -> ^Draw_Data ---
	// Demo, Debug, Information
	// create Demo window. demonstrate most ImGui features. call this to learn about the library! try to make it always available in your application!
	@(link_name = "ImGui_ShowDemoWindow")
	show_demo_window :: proc(p_open: ^bool = nil) ---
	// create Metrics/Debugger window. display Dear ImGui internals: windows, draw commands, various internal state, etc.
	@(link_name = "ImGui_ShowMetricsWindow")
	show_metrics_window :: proc(p_open: ^bool = nil) ---
	// create Debug Log window. display a simplified log of important dear imgui events.
	@(link_name = "ImGui_ShowDebugLogWindow")
	show_debug_log_window :: proc(p_open: ^bool = nil) ---
	// create Stack Tool window. hover items with mouse to query information about the source of their unique ID.
	@(link_name = "ImGui_ShowIDStackToolWindow")
	show_id_stack_tool_window :: proc(p_open: ^bool = nil) ---
	// create About window. display Dear ImGui version, credits and build/system information.
	@(link_name = "ImGui_ShowAboutWindow")
	show_about_window :: proc(p_open: ^bool = nil) ---
	// add style editor block (not a window). you can pass in a reference ImGuiStyle structure to compare to, revert to and save to (else it uses the default style)
	@(link_name = "ImGui_ShowStyleEditor")
	show_style_editor :: proc(ref: ^Style = nil) ---
	// add style selector block (not a window), essentially a combo listing the default styles.
	@(link_name = "ImGui_ShowStyleSelector")
	show_style_selector :: proc(label: cstring) -> bool ---
	// add font selector block (not a window), essentially a combo listing the loaded fonts.
	@(link_name = "ImGui_ShowFontSelector")
	show_font_selector :: proc(label: cstring) ---
	// add basic help/info block (not a window): how to manipulate ImGui as an end-user (mouse/keyboard controls).
	@(link_name = "ImGui_ShowUserGuide")
	show_user_guide :: proc() ---
	// get the compiled version string e.g. "1.80 WIP" (essentially the value for IMGUI_VERSION from the compiled version of imgui.cpp)
	@(link_name = "ImGui_GetVersion")
	get_version :: proc() -> cstring ---
	// Styles
	// new, recommended style (default)
	@(link_name = "ImGui_StyleColorsDark")
	style_colors_dark :: proc(dst: ^Style = nil) ---
	// best used with borders and a custom, thicker font
	@(link_name = "ImGui_StyleColorsLight")
	style_colors_light :: proc(dst: ^Style = nil) ---
	// classic imgui style
	@(link_name = "ImGui_StyleColorsClassic")
	style_colors_classic :: proc(dst: ^Style = nil) ---
	// Windows
	// - Begin() = push window to the stack and start appending to it. End() = pop window from the stack.
	// - Passing 'bool* p_open != NULL' shows a window-closing widget in the upper-right corner of the window,
	//   which clicking will set the boolean to false when clicked.
	// - You may append multiple times to the same window during the same frame by calling Begin()/End() pairs multiple times.
	//   Some information such as 'flags' or 'p_open' will only be considered by the first call to Begin().
	// - Begin() return false to indicate the window is collapsed or fully clipped, so you may early out and omit submitting
	//   anything to the window. Always call a matching End() for each Begin() call, regardless of its return value!
	//   [Important: due to legacy reason, Begin/End and BeginChild/EndChild are inconsistent with all other functions
	//    such as BeginMenu/EndMenu, BeginPopup/EndPopup, etc. where the EndXXX call should only be called if the corresponding
	//    BeginXXX function returned true. Begin and BeginChild are the only odd ones out. Will be fixed in a future update.]
	// - Note that the bottom of window stack always contains a window called "Debug".
	@(link_name = "ImGui_Begin")
	begin :: proc(name: cstring, p_open: ^bool = nil, flags: Window_Flags = {}) -> bool ---
	@(link_name = "ImGui_End")
	end :: proc() ---
	// Child Windows
	// - Use child windows to begin into a self-contained independent scrolling/clipping regions within a host window. Child windows can embed their own child.
	// - Before 1.90 (November 2023), the "ImGuiChildFlags child_flags = 0" parameter was "bool border = false".
	//   This API is backward compatible with old code, as we guarantee that ImGuiChildFlags_Borders == true.
	//   Consider updating your old code:
	//      BeginChild("Name", size, false)   -> Begin("Name", size, 0); or Begin("Name", size, ImGuiChildFlags_None);
	//      BeginChild("Name", size, true)    -> Begin("Name", size, ImGuiChildFlags_Borders);
	// - Manual sizing (each axis can use a different setting e.g. ImVec2(0.0f, 400.0f)):
	//     == 0.0f: use remaining parent window size for this axis.
	//      > 0.0f: use specified size for this axis.
	//      < 0.0f: right/bottom-align to specified distance from available content boundaries.
	// - Specifying ImGuiChildFlags_AutoResizeX or ImGuiChildFlags_AutoResizeY makes the sizing automatic based on child contents.
	//   Combining both ImGuiChildFlags_AutoResizeX _and_ ImGuiChildFlags_AutoResizeY defeats purpose of a scrolling region and is NOT recommended.
	// - BeginChild() returns false to indicate the window is collapsed or fully clipped, so you may early out and omit submitting
	//   anything to the window. Always call a matching EndChild() for each BeginChild() call, regardless of its return value.
	//   [Important: due to legacy reason, Begin/End and BeginChild/EndChild are inconsistent with all other functions
	//    such as BeginMenu/EndMenu, BeginPopup/EndPopup, etc. where the EndXXX call should only be called if the corresponding
	//    BeginXXX function returned true. Begin and BeginChild are the only odd ones out. Will be fixed in a future update.]
	@(link_name = "ImGui_BeginChild")
	begin_child :: proc(str_id: cstring, size: Vec2 = Vec2{0, 0}, child_flags: Child_Flags = {}, window_flags: Window_Flags = {}) -> bool ---
	@(link_name = "ImGui_BeginChildID")
	begin_child_id :: proc(id: ID, size: Vec2 = Vec2{0, 0}, child_flags: Child_Flags = {}, window_flags: Window_Flags = {}) -> bool ---
	@(link_name = "ImGui_EndChild")
	end_child :: proc() ---
	// Windows Utilities
	// - 'current window' = the window we are appending into while inside a Begin()/End() block. 'next window' = next window we will Begin() into.
	@(link_name = "ImGui_IsWindowAppearing")
	is_window_appearing :: proc() -> bool ---
	@(link_name = "ImGui_IsWindowCollapsed")
	is_window_collapsed :: proc() -> bool ---
	// is current window focused? or its root/child, depending on flags. see flags for options.
	@(link_name = "ImGui_IsWindowFocused")
	is_window_focused :: proc(flags: Focused_Flags = {}) -> bool ---
	// is current window hovered and hoverable (e.g. not blocked by a popup/modal)? See ImGuiHoveredFlags_ for options. IMPORTANT: If you are trying to check whether your mouse should be dispatched to Dear ImGui or to your underlying app, you should not use this function! Use the 'io.WantCaptureMouse' boolean for that! Refer to FAQ entry "How can I tell whether to dispatch mouse/keyboard to Dear ImGui or my application?" for details.
	@(link_name = "ImGui_IsWindowHovered")
	is_window_hovered :: proc(flags: Hovered_Flags = {}) -> bool ---
	// get draw list associated to the current window, to append your own drawing primitives
	@(link_name = "ImGui_GetWindowDrawList")
	get_window_draw_list :: proc() -> ^Draw_List ---
	// get DPI scale currently associated to the current window's viewport.
	@(link_name = "ImGui_GetWindowDpiScale")
	get_window_dpi_scale :: proc() -> f32 ---
	// get current window position in screen space (IT IS UNLIKELY YOU EVER NEED TO USE THIS. Consider always using GetCursorScreenPos() and GetContentRegionAvail() instead)
	@(link_name = "ImGui_GetWindowPos")
	get_window_pos :: proc() -> Vec2 ---
	// get current window size (IT IS UNLIKELY YOU EVER NEED TO USE THIS. Consider always using GetCursorScreenPos() and GetContentRegionAvail() instead)
	@(link_name = "ImGui_GetWindowSize")
	get_window_size :: proc() -> Vec2 ---
	// get current window width (IT IS UNLIKELY YOU EVER NEED TO USE THIS). Shortcut for GetWindowSize().x.
	@(link_name = "ImGui_GetWindowWidth")
	get_window_width :: proc() -> f32 ---
	// get current window height (IT IS UNLIKELY YOU EVER NEED TO USE THIS). Shortcut for GetWindowSize().y.
	@(link_name = "ImGui_GetWindowHeight")
	get_window_height :: proc() -> f32 ---
	// get viewport currently associated to the current window.
	@(link_name = "ImGui_GetWindowViewport")
	get_window_viewport :: proc() -> ^Viewport ---
	// Window manipulation
	// - Prefer using SetNextXXX functions (before Begin) rather that SetXXX functions (after Begin).
	// set next window position. call before Begin(). use pivot=(0.5f,0.5f) to center on given point, etc.
	@(link_name = "ImGui_SetNextWindowPos")
	set_next_window_pos :: proc(pos: Vec2, cond: Cond = {}, pivot: Vec2 = Vec2{0, 0}) ---
	// set next window size. set axis to 0.0f to force an auto-fit on this axis. call before Begin()
	@(link_name = "ImGui_SetNextWindowSize")
	set_next_window_size :: proc(size: Vec2, cond: Cond = {}) ---
	// set next window size limits. use 0.0f or FLT_MAX if you don't want limits. Use -1 for both min and max of same axis to preserve current size (which itself is a constraint). Use callback to apply non-trivial programmatic constraints.
	@(link_name = "ImGui_SetNextWindowSizeConstraints")
	set_next_window_size_constraints :: proc(size_min: Vec2, size_max: Vec2, custom_callback: Size_Callback = nil, custom_callback_data: rawptr = nil) ---
	// set next window content size (~ scrollable client area, which enforce the range of scrollbars). Not including window decorations (title bar, menu bar, etc.) nor WindowPadding. set an axis to 0.0f to leave it automatic. call before Begin()
	@(link_name = "ImGui_SetNextWindowContentSize")
	set_next_window_content_size :: proc(size: Vec2) ---
	// set next window collapsed state. call before Begin()
	@(link_name = "ImGui_SetNextWindowCollapsed")
	set_next_window_collapsed :: proc(collapsed: bool, cond: Cond = {}) ---
	// set next window to be focused / top-most. call before Begin()
	@(link_name = "ImGui_SetNextWindowFocus")
	set_next_window_focus :: proc() ---
	// set next window scrolling value (use < 0.0f to not affect a given axis).
	@(link_name = "ImGui_SetNextWindowScroll")
	set_next_window_scroll :: proc(scroll: Vec2) ---
	// set next window background color alpha. helper to easily override the Alpha component of ImGuiCol_WindowBg/ChildBg/PopupBg. you may also use ImGuiWindowFlags_NoBackground.
	@(link_name = "ImGui_SetNextWindowBgAlpha")
	set_next_window_bg_alpha :: proc(alpha: f32) ---
	// set next window viewport
	@(link_name = "ImGui_SetNextWindowViewport")
	set_next_window_viewport :: proc(viewport_id: ID) ---
	// (not recommended) set current window position - call within Begin()/End(). prefer using SetNextWindowPos(), as this may incur tearing and side-effects.
	@(link_name = "ImGui_SetWindowPos")
	set_window_pos :: proc(pos: Vec2, cond: Cond = {}) ---
	// (not recommended) set current window size - call within Begin()/End(). set to ImVec2(0, 0) to force an auto-fit. prefer using SetNextWindowSize(), as this may incur tearing and minor side-effects.
	@(link_name = "ImGui_SetWindowSize")
	set_window_size :: proc(size: Vec2, cond: Cond = {}) ---
	// (not recommended) set current window collapsed state. prefer using SetNextWindowCollapsed().
	@(link_name = "ImGui_SetWindowCollapsed")
	set_window_collapsed :: proc(collapsed: bool, cond: Cond = {}) ---
	// (not recommended) set current window to be focused / top-most. prefer using SetNextWindowFocus().
	@(link_name = "ImGui_SetWindowFocus")
	set_window_focus :: proc() ---
	// [OBSOLETE] set font scale. Adjust IO.FontGlobalScale if you want to scale all windows. This is an old API! For correct scaling, prefer to reload font + rebuild ImFontAtlas + call style.ScaleAllSizes().
	@(link_name = "ImGui_SetWindowFontScale")
	set_window_font_scale :: proc(scale: f32) ---
	// set named window position.
	@(link_name = "ImGui_SetWindowPosStr")
	set_window_pos_str :: proc(name: cstring, pos: Vec2, cond: Cond = {}) ---
	// set named window size. set axis to 0.0f to force an auto-fit on this axis.
	@(link_name = "ImGui_SetWindowSizeStr")
	set_window_size_str :: proc(name: cstring, size: Vec2, cond: Cond = {}) ---
	// set named window collapsed state
	@(link_name = "ImGui_SetWindowCollapsedStr")
	set_window_collapsed_str :: proc(name: cstring, collapsed: bool, cond: Cond = {}) ---
	// set named window to be focused / top-most. use NULL to remove focus.
	@(link_name = "ImGui_SetWindowFocusStr")
	set_window_focus_str :: proc(name: cstring) ---
	// Windows Scrolling
	// - Any change of Scroll will be applied at the beginning of next frame in the first call to Begin().
	// - You may instead use SetNextWindowScroll() prior to calling Begin() to avoid this delay, as an alternative to using SetScrollX()/SetScrollY().
	// get scrolling amount [0 .. GetScrollMaxX()]
	@(link_name = "ImGui_GetScrollX")
	get_scroll_x :: proc() -> f32 ---
	// get scrolling amount [0 .. GetScrollMaxY()]
	@(link_name = "ImGui_GetScrollY")
	get_scroll_y :: proc() -> f32 ---
	// set scrolling amount [0 .. GetScrollMaxX()]
	@(link_name = "ImGui_SetScrollX")
	set_scroll_x :: proc(scroll_x: f32) ---
	// set scrolling amount [0 .. GetScrollMaxY()]
	@(link_name = "ImGui_SetScrollY")
	set_scroll_y :: proc(scroll_y: f32) ---
	// get maximum scrolling amount ~~ ContentSize.x - WindowSize.x - DecorationsSize.x
	@(link_name = "ImGui_GetScrollMaxX")
	get_scroll_max_x :: proc() -> f32 ---
	// get maximum scrolling amount ~~ ContentSize.y - WindowSize.y - DecorationsSize.y
	@(link_name = "ImGui_GetScrollMaxY")
	get_scroll_max_y :: proc() -> f32 ---
	// adjust scrolling amount to make current cursor position visible. center_x_ratio=0.0: left, 0.5: center, 1.0: right. When using to make a "default/current item" visible, consider using SetItemDefaultFocus() instead.
	@(link_name = "ImGui_SetScrollHereX")
	set_scroll_here_x :: proc(center_x_ratio: f32 = 0.5) ---
	// adjust scrolling amount to make current cursor position visible. center_y_ratio=0.0: top, 0.5: center, 1.0: bottom. When using to make a "default/current item" visible, consider using SetItemDefaultFocus() instead.
	@(link_name = "ImGui_SetScrollHereY")
	set_scroll_here_y :: proc(center_y_ratio: f32 = 0.5) ---
	// adjust scrolling amount to make given position visible. Generally GetCursorStartPos() + offset to compute a valid position.
	@(link_name = "ImGui_SetScrollFromPosX")
	set_scroll_from_pos_x :: proc(local_x: f32, center_x_ratio: f32 = 0.5) ---
	// adjust scrolling amount to make given position visible. Generally GetCursorStartPos() + offset to compute a valid position.
	@(link_name = "ImGui_SetScrollFromPosY")
	set_scroll_from_pos_y :: proc(local_y: f32, center_y_ratio: f32 = 0.5) ---
	// Parameters stacks (shared)
	// use NULL as a shortcut to push default font
	@(link_name = "ImGui_PushFont")
	push_font :: proc(font: ^Font) ---
	@(link_name = "ImGui_PopFont")
	pop_font :: proc() ---
	// modify a style color. always use this if you modify the style after NewFrame().
	@(link_name = "ImGui_PushStyleColor")
	push_style_color :: proc(idx: Col, col: u32) ---
	@(link_name = "ImGui_PushStyleColorImVec4")
	push_style_color_vec4 :: proc(idx: Col, col: Vec4) ---
	@(link_name = "ImGui_PopStyleColor")
	pop_style_color :: proc(count: i32 = 1) ---
	// modify a style float variable. always use this if you modify the style after NewFrame()!
	@(link_name = "ImGui_PushStyleVar")
	push_style_var :: proc(idx: Style_Var, val: f32) ---
	// modify a style ImVec2 variable. "
	@(link_name = "ImGui_PushStyleVarImVec2")
	push_style_var_vec2 :: proc(idx: Style_Var, val: Vec2) ---
	// modify X component of a style ImVec2 variable. "
	@(link_name = "ImGui_PushStyleVarX")
	push_style_var_x :: proc(idx: Style_Var, val_x: f32) ---
	// modify Y component of a style ImVec2 variable. "
	@(link_name = "ImGui_PushStyleVarY")
	push_style_var_y :: proc(idx: Style_Var, val_y: f32) ---
	@(link_name = "ImGui_PopStyleVar")
	pop_style_var :: proc(count: i32 = 1) ---
	// modify specified shared item flag, e.g. PushItemFlag(ImGuiItemFlags_NoTabStop, true)
	@(link_name = "ImGui_PushItemFlag")
	push_item_flag :: proc(option: Item_Flags, enabled: bool) ---
	@(link_name = "ImGui_PopItemFlag")
	pop_item_flag :: proc() ---
	// Parameters stacks (current window)
	// push width of items for common large "item+label" widgets. >0.0f: width in pixels, <0.0f align xx pixels to the right of window (so -FLT_MIN always align width to the right side).
	@(link_name = "ImGui_PushItemWidth")
	push_item_width :: proc(item_width: f32) ---
	@(link_name = "ImGui_PopItemWidth")
	pop_item_width :: proc() ---
	// set width of the _next_ common large "item+label" widget. >0.0f: width in pixels, <0.0f align xx pixels to the right of window (so -FLT_MIN always align width to the right side)
	@(link_name = "ImGui_SetNextItemWidth")
	set_next_item_width :: proc(item_width: f32) ---
	// width of item given pushed settings and current cursor position. NOT necessarily the width of last item unlike most 'Item' functions.
	@(link_name = "ImGui_CalcItemWidth")
	calc_item_width :: proc() -> f32 ---
	// push word-wrapping position for Text*() commands. < 0.0f: no wrapping; 0.0f: wrap to end of window (or column); > 0.0f: wrap at 'wrap_pos_x' position in window local space
	@(link_name = "ImGui_PushTextWrapPos")
	push_text_wrap_pos :: proc(wrap_local_pos_x: f32 = 0.0) ---
	@(link_name = "ImGui_PopTextWrapPos")
	pop_text_wrap_pos :: proc() ---
	// Style read access
	// - Use the ShowStyleEditor() function to interactively see/edit the colors.
	// get current font
	@(link_name = "ImGui_GetFont")
	get_font :: proc() -> ^Font ---
	// get current font size (= height in pixels) of current font with current scale applied
	@(link_name = "ImGui_GetFontSize")
	get_font_size :: proc() -> f32 ---
	// get UV coordinate for a white pixel, useful to draw custom shapes via the ImDrawList API
	@(link_name = "ImGui_GetFontTexUvWhitePixel")
	get_font_tex_uv_white_pixel :: proc() -> Vec2 ---
	// retrieve given style color with style alpha applied and optional extra alpha multiplier, packed as a 32-bit value suitable for ImDrawList
	@(link_name = "ImGui_GetColorU32")
	get_color_u32 :: proc(idx: Col, alpha_mul: f32 = 1.0) -> u32 ---
	// retrieve given color with style alpha applied, packed as a 32-bit value suitable for ImDrawList
	@(link_name = "ImGui_GetColorU32ImVec4")
	get_color_u32vec4 :: proc(col: Vec4) -> u32 ---
	// retrieve given color with style alpha applied, packed as a 32-bit value suitable for ImDrawList
	@(link_name = "ImGui_GetColorU32ImU32")
	get_color_u32u32 :: proc(col: u32, alpha_mul: f32 = 1.0) -> u32 ---
	// retrieve style color as stored in ImGuiStyle structure. use to feed back into PushStyleColor(), otherwise use GetColorU32() to get style color with style alpha baked in.
	@(link_name = "ImGui_GetStyleColorVec4")
	get_style_color_vec4 :: proc(idx: Col) -> ^Vec4 ---
	// Layout cursor positioning
	// - By "cursor" we mean the current output position.
	// - The typical widget behavior is to output themselves at the current cursor position, then move the cursor one line down.
	// - You can call SameLine() between widgets to undo the last carriage return and output at the right of the preceding widget.
	// - YOU CAN DO 99% OF WHAT YOU NEED WITH ONLY GetCursorScreenPos() and GetContentRegionAvail().
	// - Attention! We currently have inconsistencies between window-local and absolute positions we will aim to fix with future API:
	//    - Absolute coordinate:        GetCursorScreenPos(), SetCursorScreenPos(), all ImDrawList:: functions. -> this is the preferred way forward.
	//    - Window-local coordinates:   SameLine(offset), GetCursorPos(), SetCursorPos(), GetCursorStartPos(), PushTextWrapPos()
	//    - Window-local coordinates:   GetContentRegionMax(), GetWindowContentRegionMin(), GetWindowContentRegionMax() --> all obsoleted. YOU DON'T NEED THEM.
	// - GetCursorScreenPos() = GetCursorPos() + GetWindowPos(). GetWindowPos() is almost only ever useful to convert from window-local to absolute coordinates. Try not to use it.
	// cursor position, absolute coordinates. THIS IS YOUR BEST FRIEND (prefer using this rather than GetCursorPos(), also more useful to work with ImDrawList API).
	@(link_name = "ImGui_GetCursorScreenPos")
	get_cursor_screen_pos :: proc() -> Vec2 ---
	// cursor position, absolute coordinates. THIS IS YOUR BEST FRIEND.
	@(link_name = "ImGui_SetCursorScreenPos")
	set_cursor_screen_pos :: proc(pos: Vec2) ---
	// available space from current position. THIS IS YOUR BEST FRIEND.
	@(link_name = "ImGui_GetContentRegionAvail")
	get_content_region_avail :: proc() -> Vec2 ---
	// [window-local] cursor position in window-local coordinates. This is not your best friend.
	@(link_name = "ImGui_GetCursorPos")
	get_cursor_pos :: proc() -> Vec2 ---
	// [window-local] "
	@(link_name = "ImGui_GetCursorPosX")
	get_cursor_pos_x :: proc() -> f32 ---
	// [window-local] "
	@(link_name = "ImGui_GetCursorPosY")
	get_cursor_pos_y :: proc() -> f32 ---
	// [window-local] "
	@(link_name = "ImGui_SetCursorPos")
	set_cursor_pos :: proc(local_pos: Vec2) ---
	// [window-local] "
	@(link_name = "ImGui_SetCursorPosX")
	set_cursor_pos_x :: proc(local_x: f32) ---
	// [window-local] "
	@(link_name = "ImGui_SetCursorPosY")
	set_cursor_pos_y :: proc(local_y: f32) ---
	// [window-local] initial cursor position, in window-local coordinates. Call GetCursorScreenPos() after Begin() to get the absolute coordinates version.
	@(link_name = "ImGui_GetCursorStartPos")
	get_cursor_start_pos :: proc() -> Vec2 ---
	// Other layout functions
	// separator, generally horizontal. inside a menu bar or in horizontal layout mode, this becomes a vertical separator.
	@(link_name = "ImGui_Separator")
	separator :: proc() ---
	// call between widgets or groups to layout them horizontally. X position given in window coordinates.
	@(link_name = "ImGui_SameLine")
	same_line :: proc(offset_from_start_x: f32 = 0.0, spacing: f32 = -1.0) ---
	// undo a SameLine() or force a new line when in a horizontal-layout context.
	@(link_name = "ImGui_NewLine")
	new_line :: proc() ---
	// add vertical spacing.
	@(link_name = "ImGui_Spacing")
	spacing :: proc() ---
	// add a dummy item of given size. unlike InvisibleButton(), Dummy() won't take the mouse click or be navigable into.
	@(link_name = "ImGui_Dummy")
	dummy :: proc(size: Vec2) ---
	// move content position toward the right, by indent_w, or style.IndentSpacing if indent_w <= 0
	@(link_name = "ImGui_Indent")
	indent :: proc(indent_w: f32 = 0.0) ---
	// move content position back to the left, by indent_w, or style.IndentSpacing if indent_w <= 0
	@(link_name = "ImGui_Unindent")
	unindent :: proc(indent_w: f32 = 0.0) ---
	// lock horizontal starting position
	@(link_name = "ImGui_BeginGroup")
	begin_group :: proc() ---
	// unlock horizontal starting position + capture the whole group bounding box into one "item" (so you can use IsItemHovered() or layout primitives such as SameLine() on whole group, etc.)
	@(link_name = "ImGui_EndGroup")
	end_group :: proc() ---
	// vertically align upcoming text baseline to FramePadding.y so that it will align properly to regularly framed items (call if you have text on a line before a framed item)
	@(link_name = "ImGui_AlignTextToFramePadding")
	align_text_to_frame_padding :: proc() ---
	// ~ FontSize
	@(link_name = "ImGui_GetTextLineHeight")
	get_text_line_height :: proc() -> f32 ---
	// ~ FontSize + style.ItemSpacing.y (distance in pixels between 2 consecutive lines of text)
	@(link_name = "ImGui_GetTextLineHeightWithSpacing")
	get_text_line_height_with_spacing :: proc() -> f32 ---
	// ~ FontSize + style.FramePadding.y * 2
	@(link_name = "ImGui_GetFrameHeight")
	get_frame_height :: proc() -> f32 ---
	// ~ FontSize + style.FramePadding.y * 2 + style.ItemSpacing.y (distance in pixels between 2 consecutive lines of framed widgets)
	@(link_name = "ImGui_GetFrameHeightWithSpacing")
	get_frame_height_with_spacing :: proc() -> f32 ---
	// ID stack/scopes
	// Read the FAQ (docs/FAQ.md or http://dearimgui.com/faq) for more details about how ID are handled in dear imgui.
	// - Those questions are answered and impacted by understanding of the ID stack system:
	//   - "Q: Why is my widget not reacting when I click on it?"
	//   - "Q: How can I have widgets with an empty label?"
	//   - "Q: How can I have multiple widgets with the same label?"
	// - Short version: ID are hashes of the entire ID stack. If you are creating widgets in a loop you most likely
	//   want to push a unique identifier (e.g. object pointer, loop index) to uniquely differentiate them.
	// - You can also use the "Label##foobar" syntax within widget label to distinguish them from each others.
	// - In this header file we use the "label"/"name" terminology to denote a string that will be displayed + used as an ID,
	//   whereas "str_id" denote a string that is only used as an ID and not normally displayed.
	// push string into the ID stack (will hash string).
	@(link_name = "ImGui_PushID")
	push_id :: proc(str_id: cstring) ---
	// push string into the ID stack (will hash string).
	@(link_name = "ImGui_PushIDStr")
	push_id_str :: proc(str_id_begin: cstring, str_id_end: cstring) ---
	// push pointer into the ID stack (will hash pointer).
	@(link_name = "ImGui_PushIDPtr")
	push_id_ptr :: proc(ptr_id: rawptr) ---
	// push integer into the ID stack (will hash integer).
	@(link_name = "ImGui_PushIDInt")
	push_id_int :: proc(int_id: i32) ---
	// pop from the ID stack.
	@(link_name = "ImGui_PopID")
	pop_id :: proc() ---
	// calculate unique ID (hash of whole ID stack + given parameter). e.g. if you want to query into ImGuiStorage yourself
	@(link_name = "ImGui_GetID")
	get_id :: proc(str_id: cstring) -> ID ---
	@(link_name = "ImGui_GetIDStr")
	get_id_str :: proc(str_id_begin: cstring, str_id_end: cstring) -> ID ---
	@(link_name = "ImGui_GetIDPtr")
	get_id_ptr :: proc(ptr_id: rawptr) -> ID ---
	@(link_name = "ImGui_GetIDInt")
	get_id_int :: proc(int_id: i32) -> ID ---
	// Widgets: Text
	// raw text without formatting. Roughly equivalent to Text("%s", text) but: A) doesn't require null terminated string if 'text_end' is specified, B) it's faster, no memory copy is done, no buffer size limits, recommended for long chunks of text.
	@(link_name = "ImGui_TextUnformatted")
	text_unformatted :: proc(text: cstring, text_end: cstring = nil) ---
	// formatted text
	@(link_name = "ImGui_Text")
	text :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// shortcut for PushStyleColor(ImGuiCol_Text, col); Text(fmt, ...); PopStyleColor();
	@(link_name = "ImGui_TextColored")
	text_colored :: proc(col: Vec4, fmt: cstring, #c_vararg args: ..any) ---
	// shortcut for PushStyleColor(ImGuiCol_Text, style.Colors[ImGuiCol_TextDisabled]); Text(fmt, ...); PopStyleColor();
	@(link_name = "ImGui_TextDisabled")
	text_disabled :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// shortcut for PushTextWrapPos(0.0f); Text(fmt, ...); PopTextWrapPos();. Note that this won't work on an auto-resizing window if there's no other widgets to extend the window width, yoy may need to set a size using SetNextWindowSize().
	@(link_name = "ImGui_TextWrapped")
	text_wrapped :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// display text+label aligned the same way as value+label widgets
	@(link_name = "ImGui_LabelText")
	label_text :: proc(label: cstring, fmt: cstring, #c_vararg args: ..any) ---
	// shortcut for Bullet()+Text()
	@(link_name = "ImGui_BulletText")
	bullet_text :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// currently: formatted text with a horizontal line
	@(link_name = "ImGui_SeparatorText")
	separator_text :: proc(label: cstring) ---
	// Widgets: Main
	// - Most widgets return true when the value has been changed or when pressed/selected
	// - You may also use one of the many IsItemXXX functions (e.g. IsItemActive, IsItemHovered, etc.) to query widget state.
	// button
	@(link_name = "ImGui_Button")
	button :: proc(label: cstring, size: Vec2 = Vec2{0, 0}) -> bool ---
	// button with (FramePadding.y == 0) to easily embed within text
	@(link_name = "ImGui_SmallButton")
	small_button :: proc(label: cstring) -> bool ---
	// flexible button behavior without the visuals, frequently useful to build custom behaviors using the public api (along with IsItemActive, IsItemHovered, etc.)
	@(link_name = "ImGui_InvisibleButton")
	invisible_button :: proc(str_id: cstring, size: Vec2, flags: Button_Flags = {}) -> bool ---
	// square button with an arrow shape
	@(link_name = "ImGui_ArrowButton")
	arrow_button :: proc(str_id: cstring, dir: Dir) -> bool ---
	@(link_name = "ImGui_Checkbox")
	checkbox :: proc(label: cstring, v: ^bool) -> bool ---
	@(link_name = "ImGui_CheckboxFlagsIntPtr")
	checkbox_flags_int_ptr :: proc(label: cstring, flags: ^i32, flags_value: i32) -> bool ---
	@(link_name = "ImGui_CheckboxFlagsUintPtr")
	checkbox_flags_uint_ptr :: proc(label: cstring, flags: ^u32, flags_value: u32) -> bool ---
	// use with e.g. if (RadioButton("one", my_value==1)) { my_value = 1; }
	@(link_name = "ImGui_RadioButton")
	radio_button :: proc(label: cstring, active: bool) -> bool ---
	// shortcut to handle the above pattern when value is an integer
	@(link_name = "ImGui_RadioButtonIntPtr")
	radio_button_int_ptr :: proc(label: cstring, v: ^i32, v_button: i32) -> bool ---
	@(link_name = "ImGui_ProgressBar")
	progress_bar :: proc(fraction: f32, size_arg: Vec2 = Vec2{-min(f32), 0}, overlay: cstring = nil) ---
	// draw a small circle + keep the cursor on the same line. advance cursor x position by GetTreeNodeToLabelSpacing(), same distance that TreeNode() uses
	@(link_name = "ImGui_Bullet")
	bullet :: proc() ---
	// hyperlink text button, return true when clicked
	@(link_name = "ImGui_TextLink")
	text_link :: proc(label: cstring) -> bool ---
	// hyperlink text button, automatically open file/url when clicked
	@(link_name = "ImGui_TextLinkOpenURL")
	text_link_open_url :: proc(label: cstring, url: cstring = nil) ---
	// Widgets: Images
	// - Read about ImTextureID here: https://github.com/ocornut/imgui/wiki/Image-Loading-and-Displaying-Examples
	// - 'uv0' and 'uv1' are texture coordinates. Read about them from the same link above.
	// - Image() pads adds style.ImageBorderSize on each side, ImageButton() adds style.FramePadding on each side.
	// - ImageButton() draws a background based on regular Button() color + optionally an inner background if specified.
	@(link_name = "ImGui_Image")
	image :: proc(user_texture_id: Texture_ID, image_size: Vec2, uv0: Vec2 = Vec2{0, 0}, uv1: Vec2 = Vec2{1, 1}) ---
	@(link_name = "ImGui_ImageWithBg")
	image_with_bg :: proc(user_texture_id: Texture_ID, image_size: Vec2, uv0: Vec2 = Vec2{0, 0}, uv1: Vec2 = Vec2{1, 1}, bg_col: Vec4 = Vec4{0, 0, 0, 0}, tint_col: Vec4 = Vec4{1, 1, 1, 1}) ---
	@(link_name = "ImGui_ImageButton")
	image_button :: proc(str_id: cstring, user_texture_id: Texture_ID, image_size: Vec2, uv0: Vec2 = Vec2{0, 0}, uv1: Vec2 = Vec2{1, 1}, bg_col: Vec4 = Vec4{0, 0, 0, 0}, tint_col: Vec4 = Vec4{1, 1, 1, 1}) -> bool ---
	// Widgets: Combo Box (Dropdown)
	// - The BeginCombo()/EndCombo() api allows you to manage your contents and selection state however you want it, by creating e.g. Selectable() items.
	// - The old Combo() api are helpers over BeginCombo()/EndCombo() which are kept available for convenience purpose. This is analogous to how ListBox are created.
	@(link_name = "ImGui_BeginCombo")
	begin_combo :: proc(label: cstring, preview_value: cstring, flags: Combo_Flags = {}) -> bool ---
	// only call EndCombo() if BeginCombo() returns true!
	@(link_name = "ImGui_EndCombo")
	end_combo :: proc() ---
	@(link_name = "ImGui_ComboChar")
	combo_char :: proc(label: cstring, current_item: ^i32, items: [^]cstring, items_count: i32, popup_max_height_in_items: i32 = -1) -> bool ---
	// Separate items with \0 within a string, end item-list with \0\0. e.g. "One\0Two\0Three\0"
	@(link_name = "ImGui_Combo")
	combo :: proc(label: cstring, current_item: ^i32, items_separated_by_zeros: cstring, popup_max_height_in_items: i32 = -1) -> bool ---
	@(link_name = "ImGui_ComboCallback")
	combo_callback :: proc(label: cstring, current_item: ^i32, getter: proc "c" (user_data: rawptr, idx: i32) -> cstring, user_data: rawptr, items_count: i32, popup_max_height_in_items: i32 = -1) -> bool ---
	// Widgets: Drag Sliders
	// - CTRL+Click on any drag box to turn them into an input box. Manually input values aren't clamped by default and can go off-bounds. Use ImGuiSliderFlags_AlwaysClamp to always clamp.
	// - For all the Float2/Float3/Float4/Int2/Int3/Int4 versions of every function, note that a 'float v[X]' function argument is the same as 'float* v',
	//   the array syntax is just a way to document the number of elements that are expected to be accessible. You can pass address of your first element out of a contiguous set, e.g. &myvector.x
	// - Adjust format string to decorate the value with a prefix, a suffix, or adapt the editing and display precision e.g. "%.3f" -> 1.234; "%5.2f secs" -> 01.23 secs; "Biscuit: %.0f" -> Biscuit: 1; etc.
	// - Format string may also be set to NULL or use the default format ("%f" or "%d").
	// - Speed are per-pixel of mouse movement (v_speed=0.2f: mouse needs to move by 5 pixels to increase value by 1). For keyboard/gamepad navigation, minimum speed is Max(v_speed, minimum_step_at_given_precision).
	// - Use v_min < v_max to clamp edits to given limits. Note that CTRL+Click manual input can override those limits if ImGuiSliderFlags_AlwaysClamp is not used.
	// - Use v_max = FLT_MAX / INT_MAX etc to avoid clamping to a maximum, same with v_min = -FLT_MAX / INT_MIN to avoid clamping to a minimum.
	// - We use the same sets of flags for DragXXX() and SliderXXX() functions as the features are the same and it makes it easier to swap them.
	// - Legacy: Pre-1.78 there are DragXXX() function signatures that take a final `float power=1.0f' argument instead of the `ImGuiSliderFlags flags=0' argument.
	//   If you get a warning converting a float to ImGuiSliderFlags, read https://github.com/ocornut/imgui/issues/3361
	// If v_min >= v_max we have no bound
	@(link_name = "ImGui_DragFloat")
	drag_float :: proc(label: cstring, v: ^f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragFloat2")
	drag_float2 :: proc(label: cstring, v: ^[2]f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragFloat3")
	drag_float3 :: proc(label: cstring, v: ^[3]f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragFloat4")
	drag_float4 :: proc(label: cstring, v: ^[4]f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragFloatRange2")
	drag_float_range2 :: proc(label: cstring, v_current_min: ^f32, v_current_max: ^f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", format_max: cstring = nil, flags: Slider_Flags = {}) -> bool ---
	// If v_min >= v_max we have no bound
	@(link_name = "ImGui_DragInt")
	drag_int :: proc(label: cstring, v: ^i32, v_speed: f32 = 1.0, v_min: i32 = 0, v_max: i32 = 0, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragInt2")
	drag_int2 :: proc(label: cstring, v: ^[2]i32, v_speed: f32 = 1.0, v_min: i32 = 0, v_max: i32 = 0, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragInt3")
	drag_int3 :: proc(label: cstring, v: ^[3]i32, v_speed: f32 = 1.0, v_min: i32 = 0, v_max: i32 = 0, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragInt4")
	drag_int4 :: proc(label: cstring, v: ^[4]i32, v_speed: f32 = 1.0, v_min: i32 = 0, v_max: i32 = 0, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragIntRange2")
	drag_int_range2 :: proc(label: cstring, v_current_min: ^i32, v_current_max: ^i32, v_speed: f32 = 1.0, v_min: i32 = 0, v_max: i32 = 0, format: cstring = "%d", format_max: cstring = nil, flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragScalar")
	drag_scalar :: proc(label: cstring, data_type: Data_Type, p_data: rawptr, v_speed: f32 = 1.0, p_min: rawptr = nil, p_max: rawptr = nil, format: cstring = nil, flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_DragScalarN")
	drag_scalar_n :: proc(label: cstring, data_type: Data_Type, p_data: rawptr, components: i32, v_speed: f32 = 1.0, p_min: rawptr = nil, p_max: rawptr = nil, format: cstring = nil, flags: Slider_Flags = {}) -> bool ---
	// Widgets: Regular Sliders
	// - CTRL+Click on any slider to turn them into an input box. Manually input values aren't clamped by default and can go off-bounds. Use ImGuiSliderFlags_AlwaysClamp to always clamp.
	// - Adjust format string to decorate the value with a prefix, a suffix, or adapt the editing and display precision e.g. "%.3f" -> 1.234; "%5.2f secs" -> 01.23 secs; "Biscuit: %.0f" -> Biscuit: 1; etc.
	// - Format string may also be set to NULL or use the default format ("%f" or "%d").
	// - Legacy: Pre-1.78 there are SliderXXX() function signatures that take a final `float power=1.0f' argument instead of the `ImGuiSliderFlags flags=0' argument.
	//   If you get a warning converting a float to ImGuiSliderFlags, read https://github.com/ocornut/imgui/issues/3361
	// adjust format to decorate the value with a prefix or a suffix for in-slider labels or unit display.
	@(link_name = "ImGui_SliderFloat")
	slider_float :: proc(label: cstring, v: ^f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderFloat2")
	slider_float2 :: proc(label: cstring, v: ^[2]f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderFloat3")
	slider_float3 :: proc(label: cstring, v: ^[3]f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderFloat4")
	slider_float4 :: proc(label: cstring, v: ^[4]f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderAngle")
	slider_angle :: proc(label: cstring, v_rad: ^f32, v_degrees_min: f32 = -360.0, v_degrees_max: f32 = +360.0, format: cstring = "%.0f deg", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt")
	slider_int :: proc(label: cstring, v: ^i32, v_min: i32, v_max: i32, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt2")
	slider_int2 :: proc(label: cstring, v: ^[2]i32, v_min: i32, v_max: i32, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt3")
	slider_int3 :: proc(label: cstring, v: ^[3]i32, v_min: i32, v_max: i32, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderInt4")
	slider_int4 :: proc(label: cstring, v: ^[4]i32, v_min: i32, v_max: i32, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderScalar")
	slider_scalar :: proc(label: cstring, data_type: Data_Type, p_data: rawptr, p_min: rawptr, p_max: rawptr, format: cstring = nil, flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_SliderScalarN")
	slider_scalar_n :: proc(label: cstring, data_type: Data_Type, p_data: rawptr, components: i32, p_min: rawptr, p_max: rawptr, format: cstring = nil, flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_VSliderFloat")
	v_slider_float :: proc(label: cstring, size: Vec2, v: ^f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_VSliderInt")
	v_slider_int :: proc(label: cstring, size: Vec2, v: ^i32, v_min: i32, v_max: i32, format: cstring = "%d", flags: Slider_Flags = {}) -> bool ---
	@(link_name = "ImGui_VSliderScalar")
	v_slider_scalar :: proc(label: cstring, size: Vec2, data_type: Data_Type, p_data: rawptr, p_min: rawptr, p_max: rawptr, format: cstring = nil, flags: Slider_Flags = {}) -> bool ---
	// Widgets: Input with Keyboard
	// - If you want to use InputText() with std::string or any custom dynamic string type, see misc/cpp/imgui_stdlib.h and comments in imgui_demo.cpp.
	// - Most of the ImGuiInputTextFlags flags are only useful for InputText() and not for InputFloatX, InputIntX, InputDouble etc.
	@(link_name = "ImGui_InputText")
	input_text :: proc(label: cstring, buf: cstring, buf_size: uint, flags: Input_Text_Flags = {}, callback: Input_Text_Callback = nil, user_data: rawptr = nil) -> bool ---
	@(link_name = "ImGui_InputTextMultiline")
	input_text_multiline :: proc(label: cstring, buf: cstring, buf_size: uint, size: Vec2 = Vec2{0, 0}, flags: Input_Text_Flags = {}, callback: Input_Text_Callback = nil, user_data: rawptr = nil) -> bool ---
	@(link_name = "ImGui_InputTextWithHint")
	input_text_with_hint :: proc(label: cstring, hint: cstring, buf: cstring, buf_size: uint, flags: Input_Text_Flags = {}, callback: Input_Text_Callback = nil, user_data: rawptr = nil) -> bool ---
	@(link_name = "ImGui_InputFloat")
	input_float :: proc(label: cstring, v: ^f32, step: f32 = 0.0, step_fast: f32 = 0.0, format: cstring = "%.3f", flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputFloat2")
	input_float2 :: proc(label: cstring, v: ^[2]f32, format: cstring = "%.3f", flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputFloat3")
	input_float3 :: proc(label: cstring, v: ^[3]f32, format: cstring = "%.3f", flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputFloat4")
	input_float4 :: proc(label: cstring, v: ^[4]f32, format: cstring = "%.3f", flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputInt")
	input_int :: proc(label: cstring, v: ^i32, step: i32 = 1, step_fast: i32 = 100, flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputInt2")
	input_int2 :: proc(label: cstring, v: ^[2]i32, flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputInt3")
	input_int3 :: proc(label: cstring, v: ^[3]i32, flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputInt4")
	input_int4 :: proc(label: cstring, v: ^[4]i32, flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputDouble")
	input_double :: proc(label: cstring, v: ^f64, step: f64 = 0.0, step_fast: f64 = 0.0, format: cstring = "%.6f", flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputScalar")
	input_scalar :: proc(label: cstring, data_type: Data_Type, p_data: rawptr, p_step: rawptr = nil, p_step_fast: rawptr = nil, format: cstring = nil, flags: Input_Text_Flags = {}) -> bool ---
	@(link_name = "ImGui_InputScalarN")
	input_scalar_n :: proc(label: cstring, data_type: Data_Type, p_data: rawptr, components: i32, p_step: rawptr = nil, p_step_fast: rawptr = nil, format: cstring = nil, flags: Input_Text_Flags = {}) -> bool ---
	// Widgets: Color Editor/Picker (tip: the ColorEdit* functions have a little color square that can be left-clicked to open a picker, and right-clicked to open an option menu.)
	// - Note that in C++ a 'float v[X]' function argument is the _same_ as 'float* v', the array syntax is just a way to document the number of elements that are expected to be accessible.
	// - You can pass the address of a first float element out of a contiguous structure, e.g. &myvector.x
	@(link_name = "ImGui_ColorEdit3")
	color_edit3 :: proc(label: cstring, col: ^[3]f32, flags: Color_Edit_Flags = {}) -> bool ---
	@(link_name = "ImGui_ColorEdit4")
	color_edit4 :: proc(label: cstring, col: ^[4]f32, flags: Color_Edit_Flags = {}) -> bool ---
	@(link_name = "ImGui_ColorPicker3")
	color_picker3 :: proc(label: cstring, col: ^[3]f32, flags: Color_Edit_Flags = {}) -> bool ---
	@(link_name = "ImGui_ColorPicker4")
	color_picker4 :: proc(label: cstring, col: ^[4]f32, flags: Color_Edit_Flags = {}, ref_col: ^f32 = nil) -> bool ---
	// display a color square/button, hover for details, return true when pressed.
	@(link_name = "ImGui_ColorButton")
	color_button :: proc(desc_id: cstring, col: Vec4, flags: Color_Edit_Flags = {}, size: Vec2 = Vec2{0, 0}) -> bool ---
	// initialize current options (generally on application startup) if you want to select a default format, picker type, etc. User will be able to change many settings, unless you pass the _NoOptions flag to your calls.
	@(link_name = "ImGui_SetColorEditOptions")
	set_color_edit_options :: proc(flags: Color_Edit_Flags) ---
	// Widgets: Trees
	// - TreeNode functions return true when the node is open, in which case you need to also call TreePop() when you are finished displaying the tree node contents.
	@(link_name = "ImGui_TreeNode")
	tree_node :: proc(label: cstring) -> bool ---
	// helper variation to easily decorelate the id from the displayed string. Read the FAQ about why and how to use ID. to align arbitrary text at the same level as a TreeNode() you can use Bullet().
	@(link_name = "ImGui_TreeNodeStr")
	tree_node_str :: proc(str_id: cstring, fmt: cstring, #c_vararg args: ..any) -> bool ---
	// "
	@(link_name = "ImGui_TreeNodePtr")
	tree_node_ptr :: proc(ptr_id: rawptr, fmt: cstring, #c_vararg args: ..any) -> bool ---
	@(link_name = "ImGui_TreeNodeEx")
	tree_node_ex :: proc(label: cstring, flags: Tree_Node_Flags = {}) -> bool ---
	@(link_name = "ImGui_TreeNodeExStr")
	tree_node_ex_str :: proc(str_id: cstring, flags: Tree_Node_Flags, fmt: cstring, #c_vararg args: ..any) -> bool ---
	@(link_name = "ImGui_TreeNodeExPtr")
	tree_node_ex_ptr :: proc(ptr_id: rawptr, flags: Tree_Node_Flags, fmt: cstring, #c_vararg args: ..any) -> bool ---
	// ~ Indent()+PushID(). Already called by TreeNode() when returning true, but you can call TreePush/TreePop yourself if desired.
	@(link_name = "ImGui_TreePush")
	tree_push :: proc(str_id: cstring) ---
	// "
	@(link_name = "ImGui_TreePushPtr")
	tree_push_ptr :: proc(ptr_id: rawptr) ---
	// ~ Unindent()+PopID()
	@(link_name = "ImGui_TreePop")
	tree_pop :: proc() ---
	// horizontal distance preceding label when using TreeNode*() or Bullet() == (g.FontSize + style.FramePadding.x*2) for a regular unframed TreeNode
	@(link_name = "ImGui_GetTreeNodeToLabelSpacing")
	get_tree_node_to_label_spacing :: proc() -> f32 ---
	// if returning 'true' the header is open. doesn't indent nor push on ID stack. user doesn't have to call TreePop().
	@(link_name = "ImGui_CollapsingHeader")
	collapsing_header :: proc(label: cstring, flags: Tree_Node_Flags = {}) -> bool ---
	// when 'p_visible != NULL': if '*p_visible==true' display an additional small close button on upper right of the header which will set the bool to false when clicked, if '*p_visible==false' don't display the header.
	@(link_name = "ImGui_CollapsingHeaderBoolPtr")
	collapsing_header_bool_ptr :: proc(label: cstring, p_visible: ^bool, flags: Tree_Node_Flags = {}) -> bool ---
	// set next TreeNode/CollapsingHeader open state.
	@(link_name = "ImGui_SetNextItemOpen")
	set_next_item_open :: proc(is_open: bool, cond: Cond = {}) ---
	// set id to use for open/close storage (default to same as item id).
	@(link_name = "ImGui_SetNextItemStorageID")
	set_next_item_storage_id :: proc(storage_id: ID) ---
	// Widgets: Selectables
	// - A selectable highlights when hovered, and can display another color when selected.
	// - Neighbors selectable extend their highlight bounds in order to leave no gap between them. This is so a series of selected Selectable appear contiguous.
	// "bool selected" carry the selection state (read-only). Selectable() is clicked is returns true so you can modify your selection state. size.x==0.0: use remaining width, size.x>0.0: specify width. size.y==0.0: use label height, size.y>0.0: specify height
	@(link_name = "ImGui_Selectable")
	selectable :: proc(label: cstring, selected: bool = false, flags: Selectable_Flags = {}, size: Vec2 = Vec2{0, 0}) -> bool ---
	// "bool* p_selected" point to the selection state (read-write), as a convenient helper.
	@(link_name = "ImGui_SelectableBoolPtr")
	selectable_bool_ptr :: proc(label: cstring, p_selected: ^bool, flags: Selectable_Flags = {}, size: Vec2 = Vec2{0, 0}) -> bool ---
	// Multi-selection system for Selectable(), Checkbox(), TreeNode() functions [BETA]
	// - This enables standard multi-selection/range-selection idioms (CTRL+Mouse/Keyboard, SHIFT+Mouse/Keyboard, etc.) in a way that also allow a clipper to be used.
	// - ImGuiSelectionUserData is often used to store your item index within the current view (but may store something else).
	// - Read comments near ImGuiMultiSelectIO for instructions/details and see 'Demo->Widgets->Selection State & Multi-Select' for demo.
	// - TreeNode() is technically supported but... using this correctly is more complicated. You need some sort of linear/random access to your tree,
	//   which is suited to advanced trees setups already implementing filters and clipper. We will work simplifying the current demo.
	// - 'selection_size' and 'items_count' parameters are optional and used by a few features. If they are costly for you to compute, you may avoid them.
	@(link_name = "ImGui_BeginMultiSelect")
	begin_multi_select :: proc(flags: Multi_Select_Flags, selection_size: i32 = -1, items_count: i32 = -1) -> ^Multi_Select_IO ---
	@(link_name = "ImGui_EndMultiSelect")
	end_multi_select :: proc() -> ^Multi_Select_IO ---
	@(link_name = "ImGui_SetNextItemSelectionUserData")
	set_next_item_selection_user_data :: proc(selection_user_data: Selection_User_Data) ---
	// Was the last item selection state toggled? Useful if you need the per-item information _before_ reaching EndMultiSelect(). We only returns toggle _event_ in order to handle clipping correctly.
	@(link_name = "ImGui_IsItemToggledSelection")
	is_item_toggled_selection :: proc() -> bool ---
	// Widgets: List Boxes
	// - This is essentially a thin wrapper to using BeginChild/EndChild with the ImGuiChildFlags_FrameStyle flag for stylistic changes + displaying a label.
	// - If you don't need a label you can probably simply use BeginChild() with the ImGuiChildFlags_FrameStyle flag for the same result.
	// - You can submit contents and manage your selection state however you want it, by creating e.g. Selectable() or any other items.
	// - The simplified/old ListBox() api are helpers over BeginListBox()/EndListBox() which are kept available for convenience purpose. This is analoguous to how Combos are created.
	// - Choose frame width:   size.x > 0.0f: custom  /  size.x < 0.0f or -FLT_MIN: right-align   /  size.x = 0.0f (default): use current ItemWidth
	// - Choose frame height:  size.y > 0.0f: custom  /  size.y < 0.0f or -FLT_MIN: bottom-align  /  size.y = 0.0f (default): arbitrary default height which can fit ~7 items
	// open a framed scrolling region
	@(link_name = "ImGui_BeginListBox")
	begin_list_box :: proc(label: cstring, size: Vec2 = Vec2{0, 0}) -> bool ---
	// only call EndListBox() if BeginListBox() returned true!
	@(link_name = "ImGui_EndListBox")
	end_list_box :: proc() ---
	@(link_name = "ImGui_ListBox")
	list_box :: proc(label: cstring, current_item: ^i32, items: [^]cstring, items_count: i32, height_in_items: i32 = -1) -> bool ---
	@(link_name = "ImGui_ListBoxCallback")
	list_box_callback :: proc(label: cstring, current_item: ^i32, getter: proc "c" (user_data: rawptr, idx: i32) -> cstring, user_data: rawptr, items_count: i32, height_in_items: i32 = -1) -> bool ---
	// Widgets: Data Plotting
	// - Consider using ImPlot (https://github.com/epezent/implot) which is much better!
	@(link_name = "ImGui_PlotLines")
	plot_lines :: proc(label: cstring, values: ^f32, values_count: i32, values_offset: i32 = 0, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = Vec2{0, 0}, stride: i32 = size_of(f32)) ---
	@(link_name = "ImGui_PlotLinesCallback")
	plot_lines_callback :: proc(label: cstring, values_getter: proc "c" (data: rawptr, idx: i32) -> f32, data: rawptr, values_count: i32, values_offset: i32 = 0, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = Vec2{0, 0}) ---
	@(link_name = "ImGui_PlotHistogram")
	plot_histogram :: proc(label: cstring, values: ^f32, values_count: i32, values_offset: i32 = 0, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = Vec2{0, 0}, stride: i32 = size_of(f32)) ---
	@(link_name = "ImGui_PlotHistogramCallback")
	plot_histogram_callback :: proc(label: cstring, values_getter: proc "c" (data: rawptr, idx: i32) -> f32, data: rawptr, values_count: i32, values_offset: i32 = 0, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = Vec2{0, 0}) ---
	// Widgets: Menus
	// - Use BeginMenuBar() on a window ImGuiWindowFlags_MenuBar to append to its menu bar.
	// - Use BeginMainMenuBar() to create a menu bar at the top of the screen and append to it.
	// - Use BeginMenu() to create a menu. You can call BeginMenu() multiple time with the same identifier to append more items to it.
	// - Not that MenuItem() keyboardshortcuts are displayed as a convenience but _not processed_ by Dear ImGui at the moment.
	// append to menu-bar of current window (requires ImGuiWindowFlags_MenuBar flag set on parent window).
	@(link_name = "ImGui_BeginMenuBar")
	begin_menu_bar :: proc() -> bool ---
	// only call EndMenuBar() if BeginMenuBar() returns true!
	@(link_name = "ImGui_EndMenuBar")
	end_menu_bar :: proc() ---
	// create and append to a full screen menu-bar.
	@(link_name = "ImGui_BeginMainMenuBar")
	begin_main_menu_bar :: proc() -> bool ---
	// only call EndMainMenuBar() if BeginMainMenuBar() returns true!
	@(link_name = "ImGui_EndMainMenuBar")
	end_main_menu_bar :: proc() ---
	// create a sub-menu entry. only call EndMenu() if this returns true!
	@(link_name = "ImGui_BeginMenu")
	begin_menu :: proc(label: cstring, enabled: bool = true) -> bool ---
	// only call EndMenu() if BeginMenu() returns true!
	@(link_name = "ImGui_EndMenu")
	end_menu :: proc() ---
	// return true when activated.
	@(link_name = "ImGui_MenuItem")
	menu_item :: proc(label: cstring, shortcut: cstring = nil, selected: bool = false, enabled: bool = true) -> bool ---
	// return true when activated + toggle (*p_selected) if p_selected != NULL
	@(link_name = "ImGui_MenuItemBoolPtr")
	menu_item_bool_ptr :: proc(label: cstring, shortcut: cstring, p_selected: ^bool, enabled: bool = true) -> bool ---
	// Tooltips
	// - Tooltips are windows following the mouse. They do not take focus away.
	// - A tooltip window can contain items of any types.
	// - SetTooltip() is more or less a shortcut for the 'if (BeginTooltip()) { Text(...); EndTooltip(); }' idiom (with a subtlety that it discard any previously submitted tooltip)
	// begin/append a tooltip window.
	@(link_name = "ImGui_BeginTooltip")
	begin_tooltip :: proc() -> bool ---
	// only call EndTooltip() if BeginTooltip()/BeginItemTooltip() returns true!
	@(link_name = "ImGui_EndTooltip")
	end_tooltip :: proc() ---
	// set a text-only tooltip. Often used after a ImGui::IsItemHovered() check. Override any previous call to SetTooltip().
	@(link_name = "ImGui_SetTooltip")
	set_tooltip :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// Tooltips: helpers for showing a tooltip when hovering an item
	// - BeginItemTooltip() is a shortcut for the 'if (IsItemHovered(ImGuiHoveredFlags_ForTooltip) && BeginTooltip())' idiom.
	// - SetItemTooltip() is a shortcut for the 'if (IsItemHovered(ImGuiHoveredFlags_ForTooltip)) { SetTooltip(...); }' idiom.
	// - Where 'ImGuiHoveredFlags_ForTooltip' itself is a shortcut to use 'style.HoverFlagsForTooltipMouse' or 'style.HoverFlagsForTooltipNav' depending on active input type. For mouse it defaults to 'ImGuiHoveredFlags_Stationary | ImGuiHoveredFlags_DelayShort'.
	// begin/append a tooltip window if preceding item was hovered.
	@(link_name = "ImGui_BeginItemTooltip")
	begin_item_tooltip :: proc() -> bool ---
	// set a text-only tooltip if preceding item was hovered. override any previous call to SetTooltip().
	@(link_name = "ImGui_SetItemTooltip")
	set_item_tooltip :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// Popups, Modals
	//  - They block normal mouse hovering detection (and therefore most mouse interactions) behind them.
	//  - If not modal: they can be closed by clicking anywhere outside them, or by pressing ESCAPE.
	//  - Their visibility state (~bool) is held internally instead of being held by the programmer as we are used to with regular Begin*() calls.
	//  - The 3 properties above are related: we need to retain popup visibility state in the library because popups may be closed as any time.
	//  - You can bypass the hovering restriction by using ImGuiHoveredFlags_AllowWhenBlockedByPopup when calling IsItemHovered() or IsWindowHovered().
	//  - IMPORTANT: Popup identifiers are relative to the current ID stack, so OpenPopup and BeginPopup generally needs to be at the same level of the stack.
	//    This is sometimes leading to confusing mistakes. May rework this in the future.
	//  - BeginPopup(): query popup state, if open start appending into the window. Call EndPopup() afterwards if returned true. ImGuiWindowFlags are forwarded to the window.
	//  - BeginPopupModal(): block every interaction behind the window, cannot be closed by user, add a dimming background, has a title bar.
	// return true if the popup is open, and you can start outputting to it.
	@(link_name = "ImGui_BeginPopup")
	begin_popup :: proc(str_id: cstring, flags: Window_Flags = {}) -> bool ---
	// return true if the modal is open, and you can start outputting to it.
	@(link_name = "ImGui_BeginPopupModal")
	begin_popup_modal :: proc(name: cstring, p_open: ^bool = nil, flags: Window_Flags = {}) -> bool ---
	// only call EndPopup() if BeginPopupXXX() returns true!
	@(link_name = "ImGui_EndPopup")
	end_popup :: proc() ---
	// Popups: open/close functions
	//  - OpenPopup(): set popup state to open. ImGuiPopupFlags are available for opening options.
	//  - If not modal: they can be closed by clicking anywhere outside them, or by pressing ESCAPE.
	//  - CloseCurrentPopup(): use inside the BeginPopup()/EndPopup() scope to close manually.
	//  - CloseCurrentPopup() is called by default by Selectable()/MenuItem() when activated (FIXME: need some options).
	//  - Use ImGuiPopupFlags_NoOpenOverExistingPopup to avoid opening a popup if there's already one at the same level. This is equivalent to e.g. testing for !IsAnyPopupOpen() prior to OpenPopup().
	//  - Use IsWindowAppearing() after BeginPopup() to tell if a window just opened.
	//  - IMPORTANT: Notice that for OpenPopupOnItemClick() we exceptionally default flags to 1 (== ImGuiPopupFlags_MouseButtonRight) for backward compatibility with older API taking 'int mouse_button = 1' parameter
	// call to mark popup as open (don't call every frame!).
	@(link_name = "ImGui_OpenPopup")
	open_popup :: proc(str_id: cstring, popup_flags: Popup_Flags = {}) ---
	// id overload to facilitate calling from nested stacks
	@(link_name = "ImGui_OpenPopupID")
	open_popup_id :: proc(id: ID, popup_flags: Popup_Flags = {}) ---
	// helper to open popup when clicked on last item. Default to ImGuiPopupFlags_MouseButtonRight == 1. (note: actually triggers on the mouse _released_ event to be consistent with popup behaviors)
	@(link_name = "ImGui_OpenPopupOnItemClick")
	open_popup_on_item_click :: proc(str_id: cstring = nil, popup_flags: Popup_Flags = {.Mouse_Button_Right}) ---
	// manually close the popup we have begin-ed into.
	@(link_name = "ImGui_CloseCurrentPopup")
	close_current_popup :: proc() ---
	// Popups: open+begin combined functions helpers
	//  - Helpers to do OpenPopup+BeginPopup where the Open action is triggered by e.g. hovering an item and right-clicking.
	//  - They are convenient to easily create context menus, hence the name.
	//  - IMPORTANT: Notice that BeginPopupContextXXX takes ImGuiPopupFlags just like OpenPopup() and unlike BeginPopup(). For full consistency, we may add ImGuiWindowFlags to the BeginPopupContextXXX functions in the future.
	//  - IMPORTANT: Notice that we exceptionally default their flags to 1 (== ImGuiPopupFlags_MouseButtonRight) for backward compatibility with older API taking 'int mouse_button = 1' parameter, so if you add other flags remember to re-add the ImGuiPopupFlags_MouseButtonRight.
	// open+begin popup when clicked on last item. Use str_id==NULL to associate the popup to previous item. If you want to use that on a non-interactive item such as Text() you need to pass in an explicit ID here. read comments in .cpp!
	@(link_name = "ImGui_BeginPopupContextItem")
	begin_popup_context_item :: proc(str_id: cstring = nil, popup_flags: Popup_Flags = {.Mouse_Button_Right}) -> bool ---
	// open+begin popup when clicked on current window.
	@(link_name = "ImGui_BeginPopupContextWindow")
	begin_popup_context_window :: proc(str_id: cstring = nil, popup_flags: Popup_Flags = {.Mouse_Button_Right}) -> bool ---
	// open+begin popup when clicked in void (where there are no windows).
	@(link_name = "ImGui_BeginPopupContextVoid")
	begin_popup_context_void :: proc(str_id: cstring = nil, popup_flags: Popup_Flags = {.Mouse_Button_Right}) -> bool ---
	// Popups: query functions
	//  - IsPopupOpen(): return true if the popup is open at the current BeginPopup() level of the popup stack.
	//  - IsPopupOpen() with ImGuiPopupFlags_AnyPopupId: return true if any popup is open at the current BeginPopup() level of the popup stack.
	//  - IsPopupOpen() with ImGuiPopupFlags_AnyPopupId + ImGuiPopupFlags_AnyPopupLevel: return true if any popup is open.
	// return true if the popup is open.
	@(link_name = "ImGui_IsPopupOpen")
	is_popup_open :: proc(str_id: cstring, flags: Popup_Flags = {}) -> bool ---
	// Tables
	// - Full-featured replacement for old Columns API.
	// - See Demo->Tables for demo code. See top of imgui_tables.cpp for general commentary.
	// - See ImGuiTableFlags_ and ImGuiTableColumnFlags_ enums for a description of available flags.
	// The typical call flow is:
	// - 1. Call BeginTable(), early out if returning false.
	// - 2. Optionally call TableSetupColumn() to submit column name/flags/defaults.
	// - 3. Optionally call TableSetupScrollFreeze() to request scroll freezing of columns/rows.
	// - 4. Optionally call TableHeadersRow() to submit a header row. Names are pulled from TableSetupColumn() data.
	// - 5. Populate contents:
	//    - In most situations you can use TableNextRow() + TableSetColumnIndex(N) to start appending into a column.
	//    - If you are using tables as a sort of grid, where every column is holding the same type of contents,
	//      you may prefer using TableNextColumn() instead of TableNextRow() + TableSetColumnIndex().
	//      TableNextColumn() will automatically wrap-around into the next row if needed.
	//    - IMPORTANT: Comparatively to the old Columns() API, we need to call TableNextColumn() for the first column!
	//    - Summary of possible call flow:
	//        - TableNextRow() -> TableSetColumnIndex(0) -> Text("Hello 0") -> TableSetColumnIndex(1) -> Text("Hello 1")  // OK
	//        - TableNextRow() -> TableNextColumn()      -> Text("Hello 0") -> TableNextColumn()      -> Text("Hello 1")  // OK
	//        -                   TableNextColumn()      -> Text("Hello 0") -> TableNextColumn()      -> Text("Hello 1")  // OK: TableNextColumn() automatically gets to next row!
	//        - TableNextRow()                           -> Text("Hello 0")                                               // Not OK! Missing TableSetColumnIndex() or TableNextColumn()! Text will not appear!
	// - 5. Call EndTable()
	@(link_name = "ImGui_BeginTable")
	begin_table :: proc(str_id: cstring, columns: i32, flags: Table_Flags = {}, outer_size: Vec2 = Vec2{0.0, 0.0}, inner_width: f32 = 0.0) -> bool ---
	// only call EndTable() if BeginTable() returns true!
	@(link_name = "ImGui_EndTable")
	end_table :: proc() ---
	// append into the first cell of a new row.
	@(link_name = "ImGui_TableNextRow")
	table_next_row :: proc(row_flags: Table_Row_Flags = {}, min_row_height: f32 = 0.0) ---
	// append into the next column (or first column of next row if currently in last column). Return true when column is visible.
	@(link_name = "ImGui_TableNextColumn")
	table_next_column :: proc() -> bool ---
	// append into the specified column. Return true when column is visible.
	@(link_name = "ImGui_TableSetColumnIndex")
	table_set_column_index :: proc(column_n: i32) -> bool ---
	// Tables: Headers & Columns declaration
	// - Use TableSetupColumn() to specify label, resizing policy, default width/weight, id, various other flags etc.
	// - Use TableHeadersRow() to create a header row and automatically submit a TableHeader() for each column.
	//   Headers are required to perform: reordering, sorting, and opening the context menu.
	//   The context menu can also be made available in columns body using ImGuiTableFlags_ContextMenuInBody.
	// - You may manually submit headers using TableNextRow() + TableHeader() calls, but this is only useful in
	//   some advanced use cases (e.g. adding custom widgets in header row).
	// - Use TableSetupScrollFreeze() to lock columns/rows so they stay visible when scrolled.
	@(link_name = "ImGui_TableSetupColumn")
	table_setup_column :: proc(label: cstring, flags: Table_Column_Flags = {}, init_width_or_weight: f32 = 0.0, user_id: ID = {}) ---
	// lock columns/rows so they stay visible when scrolled.
	@(link_name = "ImGui_TableSetupScrollFreeze")
	table_setup_scroll_freeze :: proc(cols: i32, rows: i32) ---
	// submit one header cell manually (rarely used)
	@(link_name = "ImGui_TableHeader")
	table_header :: proc(label: cstring) ---
	// submit a row with headers cells based on data provided to TableSetupColumn() + submit context menu
	@(link_name = "ImGui_TableHeadersRow")
	table_headers_row :: proc() ---
	// submit a row with angled headers for every column with the ImGuiTableColumnFlags_AngledHeader flag. MUST BE FIRST ROW.
	@(link_name = "ImGui_TableAngledHeadersRow")
	table_angled_headers_row :: proc() ---
	// Tables: Sorting & Miscellaneous functions
	// - Sorting: call TableGetSortSpecs() to retrieve latest sort specs for the table. NULL when not sorting.
	//   When 'sort_specs->SpecsDirty == true' you should sort your data. It will be true when sorting specs have
	//   changed since last call, or the first time. Make sure to set 'SpecsDirty = false' after sorting,
	//   else you may wastefully sort your data every frame!
	// - Functions args 'int column_n' treat the default value of -1 as the same as passing the current column index.
	// get latest sort specs for the table (NULL if not sorting).  Lifetime: don't hold on this pointer over multiple frames or past any subsequent call to BeginTable().
	@(link_name = "ImGui_TableGetSortSpecs")
	table_get_sort_specs :: proc() -> ^Table_Sort_Specs ---
	// return number of columns (value passed to BeginTable)
	@(link_name = "ImGui_TableGetColumnCount")
	table_get_column_count :: proc() -> i32 ---
	// return current column index.
	@(link_name = "ImGui_TableGetColumnIndex")
	table_get_column_index :: proc() -> i32 ---
	// return current row index.
	@(link_name = "ImGui_TableGetRowIndex")
	table_get_row_index :: proc() -> i32 ---
	// return "" if column didn't have a name declared by TableSetupColumn(). Pass -1 to use current column.
	@(link_name = "ImGui_TableGetColumnName")
	table_get_column_name :: proc(column_n: i32 = -1) -> cstring ---
	// return column flags so you can query their Enabled/Visible/Sorted/Hovered status flags. Pass -1 to use current column.
	@(link_name = "ImGui_TableGetColumnFlags")
	table_get_column_flags :: proc(column_n: i32 = -1) -> Table_Column_Flags ---
	// change user accessible enabled/disabled state of a column. Set to false to hide the column. User can use the context menu to change this themselves (right-click in headers, or right-click in columns body with ImGuiTableFlags_ContextMenuInBody)
	@(link_name = "ImGui_TableSetColumnEnabled")
	table_set_column_enabled :: proc(column_n: i32, v: bool) ---
	// return hovered column. return -1 when table is not hovered. return columns_count if the unused space at the right of visible columns is hovered. Can also use (TableGetColumnFlags() & ImGuiTableColumnFlags_IsHovered) instead.
	@(link_name = "ImGui_TableGetHoveredColumn")
	table_get_hovered_column :: proc() -> i32 ---
	// change the color of a cell, row, or column. See ImGuiTableBgTarget_ flags for details.
	@(link_name = "ImGui_TableSetBgColor")
	table_set_bg_color :: proc(target: Table_Bg_Target, color: u32, column_n: i32 = -1) ---
	// Legacy Columns API (prefer using Tables!)
	// - You can also use SameLine(pos_x) to mimic simplified columns.
	@(link_name = "ImGui_Columns")
	columns :: proc(count: i32 = 1, id: cstring = nil, borders: bool = true) ---
	// next column, defaults to current row or next row if the current row is finished
	@(link_name = "ImGui_NextColumn")
	next_column :: proc() ---
	// get current column index
	@(link_name = "ImGui_GetColumnIndex")
	get_column_index :: proc() -> i32 ---
	// get column width (in pixels). pass -1 to use current column
	@(link_name = "ImGui_GetColumnWidth")
	get_column_width :: proc(column_index: i32 = -1) -> f32 ---
	// set column width (in pixels). pass -1 to use current column
	@(link_name = "ImGui_SetColumnWidth")
	set_column_width :: proc(column_index: i32, width: f32) ---
	// get position of column line (in pixels, from the left side of the contents region). pass -1 to use current column, otherwise 0..GetColumnsCount() inclusive. column 0 is typically 0.0f
	@(link_name = "ImGui_GetColumnOffset")
	get_column_offset :: proc(column_index: i32 = -1) -> f32 ---
	// set position of column line (in pixels, from the left side of the contents region). pass -1 to use current column
	@(link_name = "ImGui_SetColumnOffset")
	set_column_offset :: proc(column_index: i32, offset_x: f32) ---
	@(link_name = "ImGui_GetColumnsCount")
	get_columns_count :: proc() -> i32 ---
	// Tab Bars, Tabs
	// - Note: Tabs are automatically created by the docking system (when in 'docking' branch). Use this to create tab bars/tabs yourself.
	// create and append into a TabBar
	@(link_name = "ImGui_BeginTabBar")
	begin_tab_bar :: proc(str_id: cstring, flags: Tab_Bar_Flags = {}) -> bool ---
	// only call EndTabBar() if BeginTabBar() returns true!
	@(link_name = "ImGui_EndTabBar")
	end_tab_bar :: proc() ---
	// create a Tab. Returns true if the Tab is selected.
	@(link_name = "ImGui_BeginTabItem")
	begin_tab_item :: proc(label: cstring, p_open: ^bool = nil, flags: Tab_Item_Flags = {}) -> bool ---
	// only call EndTabItem() if BeginTabItem() returns true!
	@(link_name = "ImGui_EndTabItem")
	end_tab_item :: proc() ---
	// create a Tab behaving like a button. return true when clicked. cannot be selected in the tab bar.
	@(link_name = "ImGui_TabItemButton")
	tab_item_button :: proc(label: cstring, flags: Tab_Item_Flags = {}) -> bool ---
	// notify TabBar or Docking system of a closed tab/window ahead (useful to reduce visual flicker on reorderable tab bars). For tab-bar: call after BeginTabBar() and before Tab submissions. Otherwise call with a window name.
	@(link_name = "ImGui_SetTabItemClosed")
	set_tab_item_closed :: proc(tab_or_docked_window_label: cstring) ---
	// Docking
	// [BETA API] Enable with io.ConfigFlags |= ImGuiConfigFlags_DockingEnable.
	// Note: You can use most Docking facilities without calling any API. You DO NOT need to call DockSpace() to use Docking!
	// - Drag from window title bar or their tab to dock/undock. Hold SHIFT to disable docking.
	// - Drag from window menu button (upper-left button) to undock an entire node (all windows).
	// - When io.ConfigDockingWithShift == true, you instead need to hold SHIFT to enable docking.
	// About dockspaces:
	// - Use DockSpaceOverViewport() to create a window covering the screen or a specific viewport + a dockspace inside it.
	//   This is often used with ImGuiDockNodeFlags_PassthruCentralNode to make it transparent.
	// - Use DockSpace() to create an explicit dock node _within_ an existing window. See Docking demo for details.
	// - Important: Dockspaces need to be submitted _before_ any window they can host. Submit it early in your frame!
	// - Important: Dockspaces need to be kept alive if hidden, otherwise windows docked into it will be undocked.
	//   e.g. if you have multiple tabs with a dockspace inside each tab: submit the non-visible dockspaces with ImGuiDockNodeFlags_KeepAliveOnly.
	@(link_name = "ImGui_DockSpace")
	dock_space :: proc(dockspace_id: ID, size: Vec2 = Vec2{0, 0}, flags: Dock_Node_Flags = {}, window_class: ^Window_Class = nil) -> ID ---
	@(link_name = "ImGui_DockSpaceOverViewport")
	dock_space_over_viewport :: proc(dockspace_id: ID = {}, viewport: ^Viewport = nil, flags: Dock_Node_Flags = {}, window_class: ^Window_Class = nil) -> ID ---
	// set next window dock id
	@(link_name = "ImGui_SetNextWindowDockID")
	set_next_window_dock_id :: proc(dock_id: ID, cond: Cond = {}) ---
	// set next window class (control docking compatibility + provide hints to platform backend via custom viewport flags and platform parent/child relationship)
	@(link_name = "ImGui_SetNextWindowClass")
	set_next_window_class :: proc(window_class: ^Window_Class) ---
	@(link_name = "ImGui_GetWindowDockID")
	get_window_dock_id :: proc() -> ID ---
	// is current window docked into another window?
	@(link_name = "ImGui_IsWindowDocked")
	is_window_docked :: proc() -> bool ---
	// Logging/Capture
	// - All text output from the interface can be captured into tty/file/clipboard. By default, tree nodes are automatically opened during logging.
	// start logging to tty (stdout)
	@(link_name = "ImGui_LogToTTY")
	log_to_tty :: proc(auto_open_depth: i32 = -1) ---
	// start logging to file
	@(link_name = "ImGui_LogToFile")
	log_to_file :: proc(auto_open_depth: i32 = -1, filename: cstring = nil) ---
	// start logging to OS clipboard
	@(link_name = "ImGui_LogToClipboard")
	log_to_clipboard :: proc(auto_open_depth: i32 = -1) ---
	// stop logging (close file, etc.)
	@(link_name = "ImGui_LogFinish")
	log_finish :: proc() ---
	// helper to display buttons for logging to tty/file/clipboard
	@(link_name = "ImGui_LogButtons")
	log_buttons :: proc() ---
	// pass text data straight to log (without being displayed)
	@(link_name = "ImGui_LogText")
	log_text :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// Drag and Drop
	// - On source items, call BeginDragDropSource(), if it returns true also call SetDragDropPayload() + EndDragDropSource().
	// - On target candidates, call BeginDragDropTarget(), if it returns true also call AcceptDragDropPayload() + EndDragDropTarget().
	// - If you stop calling BeginDragDropSource() the payload is preserved however it won't have a preview tooltip (we currently display a fallback "..." tooltip, see #1725)
	// - An item can be both drag source and drop target.
	// call after submitting an item which may be dragged. when this return true, you can call SetDragDropPayload() + EndDragDropSource()
	@(link_name = "ImGui_BeginDragDropSource")
	begin_drag_drop_source :: proc(flags: Drag_Drop_Flags = {}) -> bool ---
	// type is a user defined string of maximum 32 characters. Strings starting with '_' are reserved for dear imgui internal types. Data is copied and held by imgui. Return true when payload has been accepted.
	@(link_name = "ImGui_SetDragDropPayload")
	set_drag_drop_payload :: proc(type: cstring, data: rawptr, sz: uint, cond: Cond = {}) -> bool ---
	// only call EndDragDropSource() if BeginDragDropSource() returns true!
	@(link_name = "ImGui_EndDragDropSource")
	end_drag_drop_source :: proc() ---
	// call after submitting an item that may receive a payload. If this returns true, you can call AcceptDragDropPayload() + EndDragDropTarget()
	@(link_name = "ImGui_BeginDragDropTarget")
	begin_drag_drop_target :: proc() -> bool ---
	// accept contents of a given type. If ImGuiDragDropFlags_AcceptBeforeDelivery is set you can peek into the payload before the mouse button is released.
	@(link_name = "ImGui_AcceptDragDropPayload")
	accept_drag_drop_payload :: proc(type: cstring, flags: Drag_Drop_Flags = {}) -> ^Payload ---
	// only call EndDragDropTarget() if BeginDragDropTarget() returns true!
	@(link_name = "ImGui_EndDragDropTarget")
	end_drag_drop_target :: proc() ---
	// peek directly into the current payload from anywhere. returns NULL when drag and drop is finished or inactive. use ImGuiPayload::IsDataType() to test for the payload type.
	@(link_name = "ImGui_GetDragDropPayload")
	get_drag_drop_payload :: proc() -> ^Payload ---
	// Disabling [BETA API]
	// - Disable all user interactions and dim items visuals (applying style.DisabledAlpha over current colors)
	// - Those can be nested but it cannot be used to enable an already disabled section (a single BeginDisabled(true) in the stack is enough to keep everything disabled)
	// - Tooltips windows by exception are opted out of disabling.
	// - BeginDisabled(false)/EndDisabled() essentially does nothing but is provided to facilitate use of boolean expressions (as a micro-optimization: if you have tens of thousands of BeginDisabled(false)/EndDisabled() pairs, you might want to reformulate your code to avoid making those calls)
	@(link_name = "ImGui_BeginDisabled")
	begin_disabled :: proc(disabled: bool = true) ---
	@(link_name = "ImGui_EndDisabled")
	end_disabled :: proc() ---
	// Clipping
	// - Mouse hovering is affected by ImGui::PushClipRect() calls, unlike direct calls to ImDrawList::PushClipRect() which are render only.
	@(link_name = "ImGui_PushClipRect")
	push_clip_rect :: proc(clip_rect_min: Vec2, clip_rect_max: Vec2, intersect_with_current_clip_rect: bool) ---
	@(link_name = "ImGui_PopClipRect")
	pop_clip_rect :: proc() ---
	// Focus, Activation
	// make last item the default focused item of a newly appearing window.
	@(link_name = "ImGui_SetItemDefaultFocus")
	set_item_default_focus :: proc() ---
	// focus keyboard on the next widget. Use positive 'offset' to access sub components of a multiple component widget. Use -1 to access previous widget.
	@(link_name = "ImGui_SetKeyboardFocusHere")
	set_keyboard_focus_here :: proc(offset: i32 = 0) ---
	// Keyboard/Gamepad Navigation
	// alter visibility of keyboard/gamepad cursor. by default: show when using an arrow key, hide when clicking with mouse.
	@(link_name = "ImGui_SetNavCursorVisible")
	set_nav_cursor_visible :: proc(visible: bool) ---
	// Overlapping mode
	// allow next item to be overlapped by a subsequent item. Useful with invisible buttons, selectable, treenode covering an area where subsequent items may need to be added. Note that both Selectable() and TreeNode() have dedicated flags doing this.
	@(link_name = "ImGui_SetNextItemAllowOverlap")
	set_next_item_allow_overlap :: proc() ---
	// Item/Widgets Utilities and Query Functions
	// - Most of the functions are referring to the previous Item that has been submitted.
	// - See Demo Window under "Widgets->Querying Status" for an interactive visualization of most of those functions.
	// is the last item hovered? (and usable, aka not blocked by a popup, etc.). See ImGuiHoveredFlags for more options.
	@(link_name = "ImGui_IsItemHovered")
	is_item_hovered :: proc(flags: Hovered_Flags = {}) -> bool ---
	// is the last item active? (e.g. button being held, text field being edited. This will continuously return true while holding mouse button on an item. Items that don't interact will always return false)
	@(link_name = "ImGui_IsItemActive")
	is_item_active :: proc() -> bool ---
	// is the last item focused for keyboard/gamepad navigation?
	@(link_name = "ImGui_IsItemFocused")
	is_item_focused :: proc() -> bool ---
	// is the last item hovered and mouse clicked on? (**)  == IsMouseClicked(mouse_button) && IsItemHovered()Important. (**) this is NOT equivalent to the behavior of e.g. Button(). Read comments in function definition.
	@(link_name = "ImGui_IsItemClicked")
	is_item_clicked :: proc(mouse_button: Mouse_Button = {}) -> bool ---
	// is the last item visible? (items may be out of sight because of clipping/scrolling)
	@(link_name = "ImGui_IsItemVisible")
	is_item_visible :: proc() -> bool ---
	// did the last item modify its underlying value this frame? or was pressed? This is generally the same as the "bool" return value of many widgets.
	@(link_name = "ImGui_IsItemEdited")
	is_item_edited :: proc() -> bool ---
	// was the last item just made active (item was previously inactive).
	@(link_name = "ImGui_IsItemActivated")
	is_item_activated :: proc() -> bool ---
	// was the last item just made inactive (item was previously active). Useful for Undo/Redo patterns with widgets that require continuous editing.
	@(link_name = "ImGui_IsItemDeactivated")
	is_item_deactivated :: proc() -> bool ---
	// was the last item just made inactive and made a value change when it was active? (e.g. Slider/Drag moved). Useful for Undo/Redo patterns with widgets that require continuous editing. Note that you may get false positives (some widgets such as Combo()/ListBox()/Selectable() will return true even when clicking an already selected item).
	@(link_name = "ImGui_IsItemDeactivatedAfterEdit")
	is_item_deactivated_after_edit :: proc() -> bool ---
	// was the last item open state toggled? set by TreeNode().
	@(link_name = "ImGui_IsItemToggledOpen")
	is_item_toggled_open :: proc() -> bool ---
	// is any item hovered?
	@(link_name = "ImGui_IsAnyItemHovered")
	is_any_item_hovered :: proc() -> bool ---
	// is any item active?
	@(link_name = "ImGui_IsAnyItemActive")
	is_any_item_active :: proc() -> bool ---
	// is any item focused?
	@(link_name = "ImGui_IsAnyItemFocused")
	is_any_item_focused :: proc() -> bool ---
	// get ID of last item (~~ often same ImGui::GetID(label) beforehand)
	@(link_name = "ImGui_GetItemID")
	get_item_id :: proc() -> ID ---
	// get upper-left bounding rectangle of the last item (screen space)
	@(link_name = "ImGui_GetItemRectMin")
	get_item_rect_min :: proc() -> Vec2 ---
	// get lower-right bounding rectangle of the last item (screen space)
	@(link_name = "ImGui_GetItemRectMax")
	get_item_rect_max :: proc() -> Vec2 ---
	// get size of last item
	@(link_name = "ImGui_GetItemRectSize")
	get_item_rect_size :: proc() -> Vec2 ---
	// Viewports
	// - Currently represents the Platform Window created by the application which is hosting our Dear ImGui windows.
	// - In 'docking' branch with multi-viewport enabled, we extend this concept to have multiple active viewports.
	// - In the future we will extend this concept further to also represent Platform Monitor and support a "no main platform window" operation mode.
	// return primary/default viewport. This can never be NULL.
	@(link_name = "ImGui_GetMainViewport")
	get_main_viewport :: proc() -> ^Viewport ---
	// Background/Foreground Draw Lists
	// get background draw list for the given viewport or viewport associated to the current window. this draw list will be the first rendering one. Useful to quickly draw shapes/text behind dear imgui contents.
	@(link_name = "ImGui_GetBackgroundDrawList")
	get_background_draw_list :: proc(viewport: ^Viewport = nil) -> ^Draw_List ---
	// get foreground draw list for the given viewport or viewport associated to the current window. this draw list will be the top-most rendered one. Useful to quickly draw shapes/text over dear imgui contents.
	@(link_name = "ImGui_GetForegroundDrawList")
	get_foreground_draw_list :: proc(viewport: ^Viewport = nil) -> ^Draw_List ---
	// Miscellaneous Utilities
	// test if rectangle (of given size, starting from cursor position) is visible / not clipped.
	@(link_name = "ImGui_IsRectVisibleBySize")
	is_rect_visible_by_size :: proc(size: Vec2) -> bool ---
	// test if rectangle (in screen space) is visible / not clipped. to perform coarse clipping on user's side.
	@(link_name = "ImGui_IsRectVisible")
	is_rect_visible :: proc(rect_min: Vec2, rect_max: Vec2) -> bool ---
	// get global imgui time. incremented by io.DeltaTime every frame.
	@(link_name = "ImGui_GetTime")
	get_time :: proc() -> f64 ---
	// get global imgui frame count. incremented by 1 every frame.
	@(link_name = "ImGui_GetFrameCount")
	get_frame_count :: proc() -> i32 ---
	// you may use this when creating your own ImDrawList instances.
	@(link_name = "ImGui_GetDrawListSharedData")
	get_draw_list_shared_data :: proc() -> ^Draw_List_Shared_Data ---
	// get a string corresponding to the enum value (for display, saving, etc.).
	@(link_name = "ImGui_GetStyleColorName")
	get_style_color_name :: proc(idx: Col) -> cstring ---
	// replace current window storage with our own (if you want to manipulate it yourself, typically clear subsection of it)
	@(link_name = "ImGui_SetStateStorage")
	set_state_storage :: proc(storage: ^Storage) ---
	@(link_name = "ImGui_GetStateStorage")
	get_state_storage :: proc() -> ^Storage ---
	// Text Utilities
	@(link_name = "ImGui_CalcTextSize")
	calc_text_size :: proc(text: cstring, text_end: cstring = nil, hide_text_after_double_hash: bool = false, wrap_width: f32 = -1.0) -> Vec2 ---
	// Color Utilities
	@(link_name = "ImGui_ColorConvertU32ToFloat4")
	color_convert_u32to_float4 :: proc(_in: u32) -> Vec4 ---
	@(link_name = "ImGui_ColorConvertFloat4ToU32")
	color_convert_float4to_u32 :: proc(_in: Vec4) -> u32 ---
	@(link_name = "ImGui_ColorConvertRGBtoHSV")
	color_convert_rg_bto_hsv :: proc(r: f32, g: f32, b: f32, out_h: ^f32, out_s: ^f32, out_v: ^f32) ---
	@(link_name = "ImGui_ColorConvertHSVtoRGB")
	color_convert_hs_vto_rgb :: proc(h: f32, s: f32, v: f32, out_r: ^f32, out_g: ^f32, out_b: ^f32) ---
	// Inputs Utilities: Keyboard/Mouse/Gamepad
	// - the ImGuiKey enum contains all possible keyboard, mouse and gamepad inputs (e.g. ImGuiKey_A, ImGuiKey_MouseLeft, ImGuiKey_GamepadDpadUp...).
	// - (legacy: before v1.87, we used ImGuiKey to carry native/user indices as defined by each backends. This was obsoleted in 1.87 (2022-02) and completely removed in 1.91.5 (2024-11). See https://github.com/ocornut/imgui/issues/4921)
	// - (legacy: any use of ImGuiKey will assert when key < 512 to detect passing legacy native/user indices)
	// is key being held.
	@(link_name = "ImGui_IsKeyDown")
	is_key_down :: proc(key: Key) -> bool ---
	// was key pressed (went from !Down to Down)? if repeat=true, uses io.KeyRepeatDelay / KeyRepeatRate
	@(link_name = "ImGui_IsKeyPressed")
	is_key_pressed :: proc(key: Key, repeat: bool = true) -> bool ---
	// was key released (went from Down to !Down)?
	@(link_name = "ImGui_IsKeyReleased")
	is_key_released :: proc(key: Key) -> bool ---
	// was key chord (mods + key) pressed, e.g. you can pass 'ImGuiMod_Ctrl | ImGuiKey_S' as a key-chord. This doesn't do any routing or focus check, please consider using Shortcut() function instead.
	@(link_name = "ImGui_IsKeyChordPressed")
	is_key_chord_pressed :: proc(key_chord: Key_Chord) -> bool ---
	// uses provided repeat rate/delay. return a count, most often 0 or 1 but might be >1 if RepeatRate is small enough that DeltaTime > RepeatRate
	@(link_name = "ImGui_GetKeyPressedAmount")
	get_key_pressed_amount :: proc(key: Key, repeat_delay: f32, rate: f32) -> i32 ---
	// [DEBUG] returns English name of the key. Those names are provided for debugging purpose and are not meant to be saved persistently nor compared.
	@(link_name = "ImGui_GetKeyName")
	get_key_name :: proc(key: Key) -> cstring ---
	// Override io.WantCaptureKeyboard flag next frame (said flag is left for your application to handle, typically when true it instructs your app to ignore inputs). e.g. force capture keyboard when your widget is being hovered. This is equivalent to setting "io.WantCaptureKeyboard = want_capture_keyboard"; after the next NewFrame() call.
	@(link_name = "ImGui_SetNextFrameWantCaptureKeyboard")
	set_next_frame_want_capture_keyboard :: proc(want_capture_keyboard: bool) ---
	// Inputs Utilities: Shortcut Testing & Routing [BETA]
	// - ImGuiKeyChord = a ImGuiKey + optional ImGuiMod_Alt/ImGuiMod_Ctrl/ImGuiMod_Shift/ImGuiMod_Super.
	//       ImGuiKey_C                          // Accepted by functions taking ImGuiKey or ImGuiKeyChord arguments)
	//       ImGuiMod_Ctrl | ImGuiKey_C          // Accepted by functions taking ImGuiKeyChord arguments)
	//   only ImGuiMod_XXX values are legal to combine with an ImGuiKey. You CANNOT combine two ImGuiKey values.
	// - The general idea is that several callers may register interest in a shortcut, and only one owner gets it.
	//      Parent   -> call Shortcut(Ctrl+S)    // When Parent is focused, Parent gets the shortcut.
	//        Child1 -> call Shortcut(Ctrl+S)    // When Child1 is focused, Child1 gets the shortcut (Child1 overrides Parent shortcuts)
	//        Child2 -> no call                  // When Child2 is focused, Parent gets the shortcut.
	//   The whole system is order independent, so if Child1 makes its calls before Parent, results will be identical.
	//   This is an important property as it facilitate working with foreign code or larger codebase.
	// - To understand the difference:
	//   - IsKeyChordPressed() compares mods and call IsKeyPressed() -> function has no side-effect.
	//   - Shortcut() submits a route, routes are resolved, if it currently can be routed it calls IsKeyChordPressed() -> function has (desirable) side-effects as it can prevents another call from getting the route.
	// - Visualize registered routes in 'Metrics/Debugger->Inputs'.
	@(link_name = "ImGui_Shortcut")
	shortcut :: proc(key_chord: Key_Chord, flags: Input_Flags = {}) -> bool ---
	@(link_name = "ImGui_SetNextItemShortcut")
	set_next_item_shortcut :: proc(key_chord: Key_Chord, flags: Input_Flags = {}) ---
	// Inputs Utilities: Key/Input Ownership [BETA]
	// - One common use case would be to allow your items to disable standard inputs behaviors such
	//   as Tab or Alt key handling, Mouse Wheel scrolling, etc.
	//   e.g. Button(...); SetItemKeyOwner(ImGuiKey_MouseWheelY); to make hovering/activating a button disable wheel for scrolling.
	// - Reminder ImGuiKey enum include access to mouse buttons and gamepad, so key ownership can apply to them.
	// - Many related features are still in imgui_internal.h. For instance, most IsKeyXXX()/IsMouseXXX() functions have an owner-id-aware version.
	// Set key owner to last item ID if it is hovered or active. Equivalent to 'if (IsItemHovered() || IsItemActive()) { SetKeyOwner(key, GetItemID());'.
	@(link_name = "ImGui_SetItemKeyOwner")
	set_item_key_owner :: proc(key: Key) ---
	// Inputs Utilities: Mouse
	// - To refer to a mouse button, you may use named enums in your code e.g. ImGuiMouseButton_Left, ImGuiMouseButton_Right.
	// - You can also use regular integer: it is forever guaranteed that 0=Left, 1=Right, 2=Middle.
	// - Dragging operations are only reported after mouse has moved a certain distance away from the initial clicking position (see 'lock_threshold' and 'io.MouseDraggingThreshold')
	// is mouse button held?
	@(link_name = "ImGui_IsMouseDown")
	is_mouse_down :: proc(button: Mouse_Button) -> bool ---
	// did mouse button clicked? (went from !Down to Down). Same as GetMouseClickedCount() == 1.
	@(link_name = "ImGui_IsMouseClicked")
	is_mouse_clicked :: proc(button: Mouse_Button, repeat: bool = false) -> bool ---
	// did mouse button released? (went from Down to !Down)
	@(link_name = "ImGui_IsMouseReleased")
	is_mouse_released :: proc(button: Mouse_Button) -> bool ---
	// did mouse button double-clicked? Same as GetMouseClickedCount() == 2. (note that a double-click will also report IsMouseClicked() == true)
	@(link_name = "ImGui_IsMouseDoubleClicked")
	is_mouse_double_clicked :: proc(button: Mouse_Button) -> bool ---
	// delayed mouse release (use very sparingly!). Generally used with 'delay >= io.MouseDoubleClickTime' + combined with a 'io.MouseClickedLastCount==1' test. This is a very rarely used UI idiom, but some apps use this: e.g. MS Explorer single click on an icon to rename.
	@(link_name = "ImGui_IsMouseReleasedWithDelay")
	is_mouse_released_with_delay :: proc(button: Mouse_Button, delay: f32) -> bool ---
	// return the number of successive mouse-clicks at the time where a click happen (otherwise 0).
	@(link_name = "ImGui_GetMouseClickedCount")
	get_mouse_clicked_count :: proc(button: Mouse_Button) -> i32 ---
	// is mouse hovering given bounding rect (in screen space). clipped by current clipping settings, but disregarding of other consideration of focus/window ordering/popup-block.
	@(link_name = "ImGui_IsMouseHoveringRect")
	is_mouse_hovering_rect :: proc(r_min: Vec2, r_max: Vec2, clip: bool = true) -> bool ---
	// by convention we use (-FLT_MAX,-FLT_MAX) to denote that there is no mouse available
	@(link_name = "ImGui_IsMousePosValid")
	is_mouse_pos_valid :: proc(mouse_pos: ^Vec2 = nil) -> bool ---
	// [WILL OBSOLETE] is any mouse button held? This was designed for backends, but prefer having backend maintain a mask of held mouse buttons, because upcoming input queue system will make this invalid.
	@(link_name = "ImGui_IsAnyMouseDown")
	is_any_mouse_down :: proc() -> bool ---
	// shortcut to ImGui::GetIO().MousePos provided by user, to be consistent with other calls
	@(link_name = "ImGui_GetMousePos")
	get_mouse_pos :: proc() -> Vec2 ---
	// retrieve mouse position at the time of opening popup we have BeginPopup() into (helper to avoid user backing that value themselves)
	@(link_name = "ImGui_GetMousePosOnOpeningCurrentPopup")
	get_mouse_pos_on_opening_current_popup :: proc() -> Vec2 ---
	// is mouse dragging? (uses io.MouseDraggingThreshold if lock_threshold < 0.0f)
	@(link_name = "ImGui_IsMouseDragging")
	is_mouse_dragging :: proc(button: Mouse_Button, lock_threshold: f32 = -1.0) -> bool ---
	// return the delta from the initial clicking position while the mouse button is pressed or was just released. This is locked and return 0.0f until the mouse moves past a distance threshold at least once (uses io.MouseDraggingThreshold if lock_threshold < 0.0f)
	@(link_name = "ImGui_GetMouseDragDelta")
	get_mouse_drag_delta :: proc(button: Mouse_Button = {}, lock_threshold: f32 = -1.0) -> Vec2 ---
	//
	@(link_name = "ImGui_ResetMouseDragDelta")
	reset_mouse_drag_delta :: proc(button: Mouse_Button = {}) ---
	// get desired mouse cursor shape. Important: reset in ImGui::NewFrame(), this is updated during the frame. valid before Render(). If you use software rendering by setting io.MouseDrawCursor ImGui will render those for you
	@(link_name = "ImGui_GetMouseCursor")
	get_mouse_cursor :: proc() -> Mouse_Cursor ---
	// set desired mouse cursor shape
	@(link_name = "ImGui_SetMouseCursor")
	set_mouse_cursor :: proc(cursor_type: Mouse_Cursor) ---
	// Override io.WantCaptureMouse flag next frame (said flag is left for your application to handle, typical when true it instucts your app to ignore inputs). This is equivalent to setting "io.WantCaptureMouse = want_capture_mouse;" after the next NewFrame() call.
	@(link_name = "ImGui_SetNextFrameWantCaptureMouse")
	set_next_frame_want_capture_mouse :: proc(want_capture_mouse: bool) ---
	// Clipboard Utilities
	// - Also see the LogToClipboard() function to capture GUI into clipboard, or easily output text data to the clipboard.
	@(link_name = "ImGui_GetClipboardText")
	get_clipboard_text :: proc() -> cstring ---
	@(link_name = "ImGui_SetClipboardText")
	set_clipboard_text :: proc(text: cstring) ---
	// Settings/.Ini Utilities
	// - The disk functions are automatically called if io.IniFilename != NULL (default is "imgui.ini").
	// - Set io.IniFilename to NULL to load/save manually. Read io.WantSaveIniSettings description about handling .ini saving manually.
	// - Important: default value "imgui.ini" is relative to current working dir! Most apps will want to lock this to an absolute path (e.g. same path as executables).
	// call after CreateContext() and before the first call to NewFrame(). NewFrame() automatically calls LoadIniSettingsFromDisk(io.IniFilename).
	@(link_name = "ImGui_LoadIniSettingsFromDisk")
	load_ini_settings_from_disk :: proc(ini_filename: cstring) ---
	// call after CreateContext() and before the first call to NewFrame() to provide .ini data from your own data source.
	@(link_name = "ImGui_LoadIniSettingsFromMemory")
	load_ini_settings_from_memory :: proc(ini_data: cstring, ini_size: uint = {}) ---
	// this is automatically called (if io.IniFilename is not empty) a few seconds after any modification that should be reflected in the .ini file (and also by DestroyContext).
	@(link_name = "ImGui_SaveIniSettingsToDisk")
	save_ini_settings_to_disk :: proc(ini_filename: cstring) ---
	// return a zero-terminated string with the .ini data which you can save by your own mean. call when io.WantSaveIniSettings is set, then save data by your own mean and clear io.WantSaveIniSettings.
	@(link_name = "ImGui_SaveIniSettingsToMemory")
	save_ini_settings_to_memory :: proc(out_ini_size: ^uint = nil) -> cstring ---
	// Debug Utilities
	// - Your main debugging friend is the ShowMetricsWindow() function, which is also accessible from Demo->Tools->Metrics Debugger
	@(link_name = "ImGui_DebugTextEncoding")
	debug_text_encoding :: proc(text: cstring) ---
	@(link_name = "ImGui_DebugFlashStyleColor")
	debug_flash_style_color :: proc(idx: Col) ---
	@(link_name = "ImGui_DebugStartItemPicker")
	debug_start_item_picker :: proc() ---
	// This is called by IMGUI_CHECKVERSION() macro.
	@(link_name = "ImGui_DebugCheckVersionAndDataLayout")
	debug_check_version_and_data_layout :: proc(version_str: cstring, sz_io: uint, sz_style: uint, sz_vec2: uint, sz_vec4: uint, sz_drawvert: uint, sz_drawidx: uint) -> bool ---
	// Call via IMGUI_DEBUG_LOG() for maximum stripping in caller code!
	@(link_name = "ImGui_DebugLog")
	debug_log :: proc(fmt: cstring, #c_vararg args: ..any) ---
	// Memory Allocators
	// - Those functions are not reliant on the current context.
	// - DLL users: heaps and globals are not shared across DLL boundaries! You will need to call SetCurrentContext() + SetAllocatorFunctions()
	//   for each static/DLL boundary you are calling from. Read "Context and Memory Allocators" section of imgui.cpp for more details.
	@(link_name = "ImGui_SetAllocatorFunctions")
	set_allocator_functions :: proc(alloc_func: Mem_Alloc_Func, free_func: Mem_Free_Func, user_data: rawptr = nil) ---
	@(link_name = "ImGui_GetAllocatorFunctions")
	get_allocator_functions :: proc(p_alloc_func: ^Mem_Alloc_Func, p_free_func: ^Mem_Free_Func, p_user_data: ^rawptr) ---
	@(link_name = "ImGui_MemAlloc")
	mem_alloc :: proc(size: uint) -> rawptr ---
	@(link_name = "ImGui_MemFree")
	mem_free :: proc(ptr: rawptr) ---
	// (Optional) Platform/OS interface for multi-viewport support
	// Read comments around the ImGuiPlatformIO structure for more details.
	// Note: You may use GetWindowViewport() to get the current viewport of the current window.
	// call in main loop. will call CreateWindow/ResizeWindow/etc. platform functions for each secondary viewport, and DestroyWindow for each inactive viewport.
	@(link_name = "ImGui_UpdatePlatformWindows")
	update_platform_windows :: proc() ---
	// call in main loop. will call RenderWindow/SwapBuffers platform functions for each secondary viewport which doesn't have the ImGuiViewportFlags_Minimized flag set. May be reimplemented by user for custom rendering needs.
	@(link_name = "ImGui_RenderPlatformWindowsDefault")
	render_platform_windows_default :: proc(platform_render_arg: rawptr = nil, renderer_render_arg: rawptr = nil) ---
	// call DestroyWindow platform functions for all viewports. call from backend Shutdown() if you need to close platform windows before imgui shutdown. otherwise will be called by DestroyContext().
	@(link_name = "ImGui_DestroyPlatformWindows")
	destroy_platform_windows :: proc() ---
	// this is a helper for backends.
	@(link_name = "ImGui_FindViewportByID")
	find_viewport_by_id :: proc(id: ID) -> ^Viewport ---
	// this is a helper for backends. the type platform_handle is decided by the backend (e.g. HWND, MyWindow*, GLFWwindow* etc.)
	@(link_name = "ImGui_FindViewportByPlatformHandle")
	find_viewport_by_platform_handle :: proc(platform_handle: rawptr) -> ^Viewport ---
	// Construct a zero-size ImVector<> (of any type). This is primarily useful when calling ImFontGlyphRangesBuilder_BuildRanges()
	@(link_name = "ImVector_Construct")
	vector_construct :: proc(vector: rawptr) ---
	// Destruct an ImVector<> (of any type). Important: Frees the vector memory but does not call destructors on contained objects (if they have them)
	@(link_name = "ImVector_Destruct")
	vector_destruct :: proc(vector: rawptr) ---
	@(link_name = "ImGuiStyle_ScaleAllSizes")
	style_scale_all_sizes :: proc(self: ^Style, scale_factor: f32) ---
	// Input Functions
	// Queue a new key down/up event. Key should be "translated" (as in, generally ImGuiKey_A matches the key end-user would use to emit an 'A' character)
	@(link_name = "ImGuiIO_AddKeyEvent")
	io_add_key_event :: proc(self: ^IO, key: Key, down: bool) ---
	// Queue a new key down/up event for analog values (e.g. ImGuiKey_Gamepad_ values). Dead-zones should be handled by the backend.
	@(link_name = "ImGuiIO_AddKeyAnalogEvent")
	io_add_key_analog_event :: proc(self: ^IO, key: Key, down: bool, v: f32) ---
	// Queue a mouse position update. Use -FLT_MAX,-FLT_MAX to signify no mouse (e.g. app not focused and not hovered)
	@(link_name = "ImGuiIO_AddMousePosEvent")
	io_add_mouse_pos_event :: proc(self: ^IO, x: f32, y: f32) ---
	// Queue a mouse button change
	@(link_name = "ImGuiIO_AddMouseButtonEvent")
	io_add_mouse_button_event :: proc(self: ^IO, button: i32, down: bool) ---
	// Queue a mouse wheel update. wheel_y<0: scroll down, wheel_y>0: scroll up, wheel_x<0: scroll right, wheel_x>0: scroll left.
	@(link_name = "ImGuiIO_AddMouseWheelEvent")
	io_add_mouse_wheel_event :: proc(self: ^IO, wheel_x: f32, wheel_y: f32) ---
	// Queue a mouse source change (Mouse/TouchScreen/Pen)
	@(link_name = "ImGuiIO_AddMouseSourceEvent")
	io_add_mouse_source_event :: proc(self: ^IO, source: Mouse_Source) ---
	// Queue a mouse hovered viewport. Requires backend to set ImGuiBackendFlags_HasMouseHoveredViewport to call this (for multi-viewport support).
	@(link_name = "ImGuiIO_AddMouseViewportEvent")
	io_add_mouse_viewport_event :: proc(self: ^IO, id: ID) ---
	// Queue a gain/loss of focus for the application (generally based on OS/platform focus of your window)
	@(link_name = "ImGuiIO_AddFocusEvent")
	io_add_focus_event :: proc(self: ^IO, focused: bool) ---
	// Queue a new character input
	@(link_name = "ImGuiIO_AddInputCharacter")
	io_add_input_character :: proc(self: ^IO, c: u32) ---
	// Queue a new character input from a UTF-16 character, it can be a surrogate
	@(link_name = "ImGuiIO_AddInputCharacterUTF16")
	io_add_input_character_utf16 :: proc(self: ^IO, c: Wchar16) ---
	// Queue a new characters input from a UTF-8 string
	@(link_name = "ImGuiIO_AddInputCharactersUTF8")
	io_add_input_characters_utf8 :: proc(self: ^IO, str: cstring) ---
	// [Optional] Specify index for legacy <1.87 IsKeyXXX() functions with native indices + specify native keycode, scancode.
	@(link_name = "ImGuiIO_SetKeyEventNativeData")
	io_set_key_event_native_data :: proc(self: ^IO, key: Key, native_keycode: i32, native_scancode: i32, native_legacy_index: i32 = -1) ---
	// Set master flag for accepting key/mouse/text events (default to true). Useful if you have native dialog boxes that are interrupting your application loop/refresh, and you want to disable events being queued while your app is frozen.
	@(link_name = "ImGuiIO_SetAppAcceptingEvents")
	io_set_app_accepting_events :: proc(self: ^IO, accepting_events: bool) ---
	// Clear all incoming events.
	@(link_name = "ImGuiIO_ClearEventsQueue")
	io_clear_events_queue :: proc(self: ^IO) ---
	// Clear current keyboard/gamepad state + current frame text input buffer. Equivalent to releasing all keys/buttons.
	@(link_name = "ImGuiIO_ClearInputKeys")
	io_clear_input_keys :: proc(self: ^IO) ---
	// Clear current mouse state.
	@(link_name = "ImGuiIO_ClearInputMouse")
	io_clear_input_mouse :: proc(self: ^IO) ---
	@(link_name = "ImGuiInputTextCallbackData_DeleteChars")
	input_text_callback_data_delete_chars :: proc(self: ^Input_Text_Callback_Data, pos: i32, bytes_count: i32) ---
	@(link_name = "ImGuiInputTextCallbackData_InsertChars")
	input_text_callback_data_insert_chars :: proc(self: ^Input_Text_Callback_Data, pos: i32, text: cstring, text_end: cstring = nil) ---
	@(link_name = "ImGuiInputTextCallbackData_SelectAll")
	input_text_callback_data_select_all :: proc(self: ^Input_Text_Callback_Data) ---
	@(link_name = "ImGuiInputTextCallbackData_ClearSelection")
	input_text_callback_data_clear_selection :: proc(self: ^Input_Text_Callback_Data) ---
	@(link_name = "ImGuiInputTextCallbackData_HasSelection")
	input_text_callback_data_has_selection :: proc(self: ^Input_Text_Callback_Data) -> bool ---
	@(link_name = "ImGuiPayload_Clear")
	payload_clear :: proc(self: ^Payload) ---
	@(link_name = "ImGuiPayload_IsDataType")
	payload_is_data_type :: proc(self: ^Payload, type: cstring) -> bool ---
	@(link_name = "ImGuiPayload_IsPreview")
	payload_is_preview :: proc(self: ^Payload) -> bool ---
	@(link_name = "ImGuiPayload_IsDelivery")
	payload_is_delivery :: proc(self: ^Payload) -> bool ---
	@(link_name = "ImGuiTextFilter_ImGuiTextRange_empty")
	text_filter_gui_text_range_empty :: proc(self: ^Text_Filter_Gui_Text_Range) -> bool ---
	@(link_name = "ImGuiTextFilter_ImGuiTextRange_split")
	text_filter_gui_text_range_split :: proc(self: ^Text_Filter_Gui_Text_Range, separator: cstring, out: ^Vector_Gui_Text_Filter_Gui_Text_Range) ---
	// Helper calling InputText+Build
	@(link_name = "ImGuiTextFilter_Draw")
	text_filter_draw :: proc(self: ^Text_Filter, label: cstring = "Filter (inc,-exc)", width: f32 = 0.0) -> bool ---
	@(link_name = "ImGuiTextFilter_PassFilter")
	text_filter_pass_filter :: proc(self: ^Text_Filter, text: cstring, text_end: cstring = nil) -> bool ---
	@(link_name = "ImGuiTextFilter_Build")
	text_filter_build :: proc(self: ^Text_Filter) ---
	@(link_name = "ImGuiTextFilter_Clear")
	text_filter_clear :: proc(self: ^Text_Filter) ---
	@(link_name = "ImGuiTextFilter_IsActive")
	text_filter_is_active :: proc(self: ^Text_Filter) -> bool ---
	@(link_name = "ImGuiTextBuffer_begin")
	text_buffer_begin :: proc(self: ^Text_Buffer) -> cstring ---
	// Buf is zero-terminated, so end() will point on the zero-terminator
	@(link_name = "ImGuiTextBuffer_end")
	text_buffer_end :: proc(self: ^Text_Buffer) -> cstring ---
	@(link_name = "ImGuiTextBuffer_size")
	text_buffer_size :: proc(self: ^Text_Buffer) -> i32 ---
	@(link_name = "ImGuiTextBuffer_empty")
	text_buffer_empty :: proc(self: ^Text_Buffer) -> bool ---
	@(link_name = "ImGuiTextBuffer_clear")
	text_buffer_clear :: proc(self: ^Text_Buffer) ---
	// Similar to resize(0) on ImVector: empty string but don't free buffer.
	@(link_name = "ImGuiTextBuffer_resize")
	text_buffer_resize :: proc(self: ^Text_Buffer, size: i32) ---
	@(link_name = "ImGuiTextBuffer_reserve")
	text_buffer_reserve :: proc(self: ^Text_Buffer, capacity: i32) ---
	@(link_name = "ImGuiTextBuffer_c_str")
	text_buffer_c_str :: proc(self: ^Text_Buffer) -> cstring ---
	@(link_name = "ImGuiTextBuffer_append")
	text_buffer_append :: proc(self: ^Text_Buffer, str: cstring, str_end: cstring = nil) ---
	@(link_name = "ImGuiTextBuffer_appendf")
	text_buffer_appendf :: proc(self: ^Text_Buffer, fmt: cstring, #c_vararg args: ..any) ---
	// - Get***() functions find pair, never add/allocate. Pairs are sorted so a query is O(log N)
	// - Set***() functions find pair, insertion on demand if missing.
	// - Sorted insertion is costly, paid once. A typical frame shouldn't need to insert any new pair.
	@(link_name = "ImGuiStorage_Clear")
	storage_clear :: proc(self: ^Storage) ---
	@(link_name = "ImGuiStorage_GetInt")
	storage_get_int :: proc(self: ^Storage, key: ID, default_val: i32 = 0) -> i32 ---
	@(link_name = "ImGuiStorage_SetInt")
	storage_set_int :: proc(self: ^Storage, key: ID, val: i32) ---
	@(link_name = "ImGuiStorage_GetBool")
	storage_get_bool :: proc(self: ^Storage, key: ID, default_val: bool = false) -> bool ---
	@(link_name = "ImGuiStorage_SetBool")
	storage_set_bool :: proc(self: ^Storage, key: ID, val: bool) ---
	@(link_name = "ImGuiStorage_GetFloat")
	storage_get_float :: proc(self: ^Storage, key: ID, default_val: f32 = 0.0) -> f32 ---
	@(link_name = "ImGuiStorage_SetFloat")
	storage_set_float :: proc(self: ^Storage, key: ID, val: f32) ---
	// default_val is NULL
	@(link_name = "ImGuiStorage_GetVoidPtr")
	storage_get_void_ptr :: proc(self: ^Storage, key: ID) -> rawptr ---
	@(link_name = "ImGuiStorage_SetVoidPtr")
	storage_set_void_ptr :: proc(self: ^Storage, key: ID, val: rawptr) ---
	// - Get***Ref() functions finds pair, insert on demand if missing, return pointer. Useful if you intend to do Get+Set.
	// - References are only valid until a new value is added to the storage. Calling a Set***() function or a Get***Ref() function invalidates the pointer.
	// - A typical use case where this is convenient for quick hacking (e.g. add storage during a live Edit&Continue session if you can't modify existing struct)
	//      float* pvar = ImGui::GetFloatRef(key); ImGui::SliderFloat("var", pvar, 0, 100.0f); some_var += *pvar;
	@(link_name = "ImGuiStorage_GetIntRef")
	storage_get_int_ref :: proc(self: ^Storage, key: ID, default_val: i32 = 0) -> ^i32 ---
	@(link_name = "ImGuiStorage_GetBoolRef")
	storage_get_bool_ref :: proc(self: ^Storage, key: ID, default_val: bool = false) -> ^bool ---
	@(link_name = "ImGuiStorage_GetFloatRef")
	storage_get_float_ref :: proc(self: ^Storage, key: ID, default_val: f32 = 0.0) -> ^f32 ---
	@(link_name = "ImGuiStorage_GetVoidPtrRef")
	storage_get_void_ptr_ref :: proc(self: ^Storage, key: ID, default_val: rawptr = nil) -> ^rawptr ---
	// Advanced: for quicker full rebuild of a storage (instead of an incremental one), you may add all your contents and then sort once.
	@(link_name = "ImGuiStorage_BuildSortByKey")
	storage_build_sort_by_key :: proc(self: ^Storage) ---
	// Obsolete: use on your own storage if you know only integer are being stored (open/close all tree nodes)
	@(link_name = "ImGuiStorage_SetAllInt")
	storage_set_all_int :: proc(self: ^Storage, val: i32) ---
	@(link_name = "ImGuiListClipper_Begin")
	list_clipper_begin :: proc(self: ^List_Clipper, items_count: i32, items_height: f32 = -1.0) ---
	// Automatically called on the last call of Step() that returns false.
	@(link_name = "ImGuiListClipper_End")
	list_clipper_end :: proc(self: ^List_Clipper) ---
	// Call until it returns false. The DisplayStart/DisplayEnd fields will be set and you can process/draw those items.
	@(link_name = "ImGuiListClipper_Step")
	list_clipper_step :: proc(self: ^List_Clipper) -> bool ---
	// Call IncludeItemByIndex() or IncludeItemsByIndex() *BEFORE* first call to Step() if you need a range of items to not be clipped, regardless of their visibility.
	// (Due to alignment / padding of certain items it is possible that an extra item may be included on either end of the display range).
	@(link_name = "ImGuiListClipper_IncludeItemByIndex")
	list_clipper_include_item_by_index :: proc(self: ^List_Clipper, item_index: i32) ---
	// item_end is exclusive e.g. use (42, 42+1) to make item 42 never clipped.
	@(link_name = "ImGuiListClipper_IncludeItemsByIndex")
	list_clipper_include_items_by_index :: proc(self: ^List_Clipper, item_begin: i32, item_end: i32) ---
	// Seek cursor toward given item. This is automatically called while stepping.
	// - The only reason to call this is: you can use ImGuiListClipper::Begin(INT_MAX) if you don't know item count ahead of time.
	// - In this case, after all steps are done, you'll want to call SeekCursorForItem(item_count).
	@(link_name = "ImGuiListClipper_SeekCursorForItem")
	list_clipper_seek_cursor_for_item :: proc(self: ^List_Clipper, item_index: i32) ---
	// FIXME-OBSOLETE: May need to obsolete/cleanup those helpers.
	@(link_name = "ImColor_SetHSV")
	color_set_hsv :: proc(self: ^Color, h: f32, s: f32, v: f32, a: f32 = 1.0) ---
	@(link_name = "ImColor_HSV")
	color_hsv :: proc(h: f32, s: f32, v: f32, a: f32 = 1.0) -> Color ---
	// Apply selection requests coming from BeginMultiSelect() and EndMultiSelect() functions. It uses 'items_count' passed to BeginMultiSelect()
	@(link_name = "ImGuiSelectionBasicStorage_ApplyRequests")
	selection_basic_storage_apply_requests :: proc(self: ^Selection_Basic_Storage, ms_io: ^Multi_Select_IO) ---
	// Query if an item id is in selection.
	@(link_name = "ImGuiSelectionBasicStorage_Contains")
	selection_basic_storage_contains :: proc(self: ^Selection_Basic_Storage, id: ID) -> bool ---
	// Clear selection
	@(link_name = "ImGuiSelectionBasicStorage_Clear")
	selection_basic_storage_clear :: proc(self: ^Selection_Basic_Storage) ---
	// Swap two selections
	@(link_name = "ImGuiSelectionBasicStorage_Swap")
	selection_basic_storage_swap :: proc(self: ^Selection_Basic_Storage, r: ^Selection_Basic_Storage) ---
	// Add/remove an item from selection (generally done by ApplyRequests() function)
	@(link_name = "ImGuiSelectionBasicStorage_SetItemSelected")
	selection_basic_storage_set_item_selected :: proc(self: ^Selection_Basic_Storage, id: ID, selected: bool) ---
	// Iterate selection with 'void* it = NULL; ImGuiID id; while (selection.GetNextSelectedItem(&it, &id)) { ... }'
	@(link_name = "ImGuiSelectionBasicStorage_GetNextSelectedItem")
	selection_basic_storage_get_next_selected_item :: proc(self: ^Selection_Basic_Storage, opaque_it: ^rawptr, out_id: ^ID) -> bool ---
	// Convert index to item id based on provided adapter.
	@(link_name = "ImGuiSelectionBasicStorage_GetStorageIdFromIndex")
	selection_basic_storage_get_storage_id_from_index :: proc(self: ^Selection_Basic_Storage, idx: i32) -> ID ---
	// Apply selection requests by using AdapterSetItemSelected() calls
	@(link_name = "ImGuiSelectionExternalStorage_ApplyRequests")
	selection_external_storage_apply_requests :: proc(self: ^Selection_External_Storage, ms_io: ^Multi_Select_IO) ---
	// Since 1.83: returns ImTextureID associated with this draw call. Warning: DO NOT assume this is always same as 'TextureId' (we will change this function for an upcoming feature)
	@(link_name = "ImDrawCmd_GetTexID")
	draw_cmd_get_tex_id :: proc(self: ^Draw_Cmd) -> Texture_ID ---
	// Do not clear Channels[] so our allocations are reused next frame
	@(link_name = "ImDrawListSplitter_Clear")
	draw_list_splitter_clear :: proc(self: ^Draw_List_Splitter) ---
	@(link_name = "ImDrawListSplitter_ClearFreeMemory")
	draw_list_splitter_clear_free_memory :: proc(self: ^Draw_List_Splitter) ---
	@(link_name = "ImDrawListSplitter_Split")
	draw_list_splitter_split :: proc(self: ^Draw_List_Splitter, draw_list: ^Draw_List, count: i32) ---
	@(link_name = "ImDrawListSplitter_Merge")
	draw_list_splitter_merge :: proc(self: ^Draw_List_Splitter, draw_list: ^Draw_List) ---
	@(link_name = "ImDrawListSplitter_SetCurrentChannel")
	draw_list_splitter_set_current_channel :: proc(self: ^Draw_List_Splitter, draw_list: ^Draw_List, channel_idx: i32) ---
	// Render-level scissoring. This is passed down to your render function but not used for CPU-side coarse clipping. Prefer using higher-level ImGui::PushClipRect() to affect logic (hit-testing and widget culling)
	@(link_name = "ImDrawList_PushClipRect")
	draw_list_push_clip_rect :: proc(self: ^Draw_List, clip_rect_min: Vec2, clip_rect_max: Vec2, intersect_with_current_clip_rect: bool = false) ---
	@(link_name = "ImDrawList_PushClipRectFullScreen")
	draw_list_push_clip_rect_full_screen :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList_PopClipRect")
	draw_list_pop_clip_rect :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList_PushTextureID")
	draw_list_push_texture_id :: proc(self: ^Draw_List, texture_id: Texture_ID) ---
	@(link_name = "ImDrawList_PopTextureID")
	draw_list_pop_texture_id :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList_GetClipRectMin")
	draw_list_get_clip_rect_min :: proc(self: ^Draw_List) -> Vec2 ---
	@(link_name = "ImDrawList_GetClipRectMax")
	draw_list_get_clip_rect_max :: proc(self: ^Draw_List) -> Vec2 ---
	// Primitives
	// - Filled shapes must always use clockwise winding order. The anti-aliasing fringe depends on it. Counter-clockwise shapes will have "inward" anti-aliasing.
	// - For rectangular primitives, "p_min" and "p_max" represent the upper-left and lower-right corners.
	// - For circle primitives, use "num_segments == 0" to automatically calculate tessellation (preferred).
	//   In older versions (until Dear ImGui 1.77) the AddCircle functions defaulted to num_segments == 12.
	//   In future versions we will use textures to provide cheaper and higher-quality circles.
	//   Use AddNgon() and AddNgonFilled() functions if you need to guarantee a specific number of sides.
	@(link_name = "ImDrawList_AddLine")
	draw_list_add_line :: proc(self: ^Draw_List, p1: Vec2, p2: Vec2, col: u32, thickness: f32 = 1.0) ---
	// a: upper-left, b: lower-right (== upper-left + size)
	@(link_name = "ImDrawList_AddRect")
	draw_list_add_rect :: proc(self: ^Draw_List, p_min: Vec2, p_max: Vec2, col: u32, rounding: f32 = 0.0, flags: Draw_Flags = {}, thickness: f32 = 1.0) ---
	// a: upper-left, b: lower-right (== upper-left + size)
	@(link_name = "ImDrawList_AddRectFilled")
	draw_list_add_rect_filled :: proc(self: ^Draw_List, p_min: Vec2, p_max: Vec2, col: u32, rounding: f32 = 0.0, flags: Draw_Flags = {}) ---
	@(link_name = "ImDrawList_AddRectFilledMultiColor")
	draw_list_add_rect_filled_multi_color :: proc(self: ^Draw_List, p_min: Vec2, p_max: Vec2, col_upr_left: u32, col_upr_right: u32, col_bot_right: u32, col_bot_left: u32) ---
	@(link_name = "ImDrawList_AddQuad")
	draw_list_add_quad :: proc(self: ^Draw_List, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, col: u32, thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddQuadFilled")
	draw_list_add_quad_filled :: proc(self: ^Draw_List, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, col: u32) ---
	@(link_name = "ImDrawList_AddTriangle")
	draw_list_add_triangle :: proc(self: ^Draw_List, p1: Vec2, p2: Vec2, p3: Vec2, col: u32, thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddTriangleFilled")
	draw_list_add_triangle_filled :: proc(self: ^Draw_List, p1: Vec2, p2: Vec2, p3: Vec2, col: u32) ---
	@(link_name = "ImDrawList_AddCircle")
	draw_list_add_circle :: proc(self: ^Draw_List, center: Vec2, radius: f32, col: u32, num_segments: i32 = 0, thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddCircleFilled")
	draw_list_add_circle_filled :: proc(self: ^Draw_List, center: Vec2, radius: f32, col: u32, num_segments: i32 = 0) ---
	@(link_name = "ImDrawList_AddNgon")
	draw_list_add_ngon :: proc(self: ^Draw_List, center: Vec2, radius: f32, col: u32, num_segments: i32, thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddNgonFilled")
	draw_list_add_ngon_filled :: proc(self: ^Draw_List, center: Vec2, radius: f32, col: u32, num_segments: i32) ---
	@(link_name = "ImDrawList_AddEllipse")
	draw_list_add_ellipse :: proc(self: ^Draw_List, center: Vec2, radius: Vec2, col: u32, rot: f32 = 0.0, num_segments: i32 = 0, thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_AddEllipseFilled")
	draw_list_add_ellipse_filled :: proc(self: ^Draw_List, center: Vec2, radius: Vec2, col: u32, rot: f32 = 0.0, num_segments: i32 = 0) ---
	@(link_name = "ImDrawList_AddText")
	draw_list_add_text :: proc(self: ^Draw_List, pos: Vec2, col: u32, text_begin: cstring, text_end: cstring = nil) ---
	@(link_name = "ImDrawList_AddTextImFontPtr")
	draw_list_add_text_font_ptr :: proc(self: ^Draw_List, font: ^Font, font_size: f32, pos: Vec2, col: u32, text_begin: cstring, text_end: cstring = nil, wrap_width: f32 = 0.0, cpu_fine_clip_rect: ^Vec4 = nil) ---
	// Cubic Bezier (4 control points)
	@(link_name = "ImDrawList_AddBezierCubic")
	draw_list_add_bezier_cubic :: proc(self: ^Draw_List, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, col: u32, thickness: f32, num_segments: i32 = 0) ---
	// Quadratic Bezier (3 control points)
	@(link_name = "ImDrawList_AddBezierQuadratic")
	draw_list_add_bezier_quadratic :: proc(self: ^Draw_List, p1: Vec2, p2: Vec2, p3: Vec2, col: u32, thickness: f32, num_segments: i32 = 0) ---
	// General polygon
	// - Only simple polygons are supported by filling functions (no self-intersections, no holes).
	// - Concave polygon fill is more expensive than convex one: it has O(N^2) complexity. Provided as a convenience for the user but not used by the main library.
	@(link_name = "ImDrawList_AddPolyline")
	draw_list_add_polyline :: proc(self: ^Draw_List, points: ^Vec2, num_points: i32, col: u32, flags: Draw_Flags, thickness: f32) ---
	@(link_name = "ImDrawList_AddConvexPolyFilled")
	draw_list_add_convex_poly_filled :: proc(self: ^Draw_List, points: ^Vec2, num_points: i32, col: u32) ---
	@(link_name = "ImDrawList_AddConcavePolyFilled")
	draw_list_add_concave_poly_filled :: proc(self: ^Draw_List, points: ^Vec2, num_points: i32, col: u32) ---
	// Image primitives
	// - Read FAQ to understand what ImTextureID is.
	// - "p_min" and "p_max" represent the upper-left and lower-right corners of the rectangle.
	// - "uv_min" and "uv_max" represent the normalized texture coordinates to use for those corners. Using (0,0)->(1,1) texture coordinates will generally display the entire texture.
	@(link_name = "ImDrawList_AddImage")
	im_draw_list_add_image :: proc(self: ^Draw_List, user_texture_id: Texture_ID, p_min: Vec2, p_max: Vec2, uv_min: Vec2 = Vec2{0, 0}, uv_max: Vec2 = Vec2{1, 1}, col: u32 = 0xff_ff_ff_ff) ---
	@(link_name = "ImDrawList_AddImageQuad")
	im_draw_list_add_image_quad :: proc(self: ^Draw_List, user_texture_id: Texture_ID, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, uv1: Vec2 = Vec2{0, 0}, uv2: Vec2 = Vec2{1, 0}, uv3: Vec2 = Vec2{1, 1}, uv4: Vec2 = Vec2{0, 1}, col: u32 = 0xff_ff_ff_ff) ---
	@(link_name = "ImDrawList_AddImageRounded")
	im_draw_list_add_image_rounded :: proc(self: ^Draw_List, user_texture_id: Texture_ID, p_min: Vec2, p_max: Vec2, uv_min: Vec2, uv_max: Vec2, col: u32, rounding: f32, flags: Draw_Flags = {}) ---
	// Stateful path API, add points then finish with PathFillConvex() or PathStroke()
	// - Important: filled shapes must always use clockwise winding order! The anti-aliasing fringe depends on it. Counter-clockwise shapes will have "inward" anti-aliasing.
	//   so e.g. 'PathArcTo(center, radius, PI * -0.5f, PI)' is ok, whereas 'PathArcTo(center, radius, PI, PI * -0.5f)' won't have correct anti-aliasing when followed by PathFillConvex().
	@(link_name = "ImDrawList_PathClear")
	draw_list_path_clear :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList_PathLineTo")
	draw_list_path_line_to :: proc(self: ^Draw_List, pos: Vec2) ---
	@(link_name = "ImDrawList_PathLineToMergeDuplicate")
	draw_list_path_line_to_merge_duplicate :: proc(self: ^Draw_List, pos: Vec2) ---
	@(link_name = "ImDrawList_PathFillConvex")
	draw_list_path_fill_convex :: proc(self: ^Draw_List, col: u32) ---
	@(link_name = "ImDrawList_PathFillConcave")
	draw_list_path_fill_concave :: proc(self: ^Draw_List, col: u32) ---
	@(link_name = "ImDrawList_PathStroke")
	draw_list_path_stroke :: proc(self: ^Draw_List, col: u32, flags: Draw_Flags = {}, thickness: f32 = 1.0) ---
	@(link_name = "ImDrawList_PathArcTo")
	draw_list_path_arc_to :: proc(self: ^Draw_List, center: Vec2, radius: f32, a_min: f32, a_max: f32, num_segments: i32 = 0) ---
	// Use precomputed angles for a 12 steps circle
	@(link_name = "ImDrawList_PathArcToFast")
	draw_list_path_arc_to_fast :: proc(self: ^Draw_List, center: Vec2, radius: f32, a_min_of_12: i32, a_max_of_12: i32) ---
	// Ellipse
	@(link_name = "ImDrawList_PathEllipticalArcTo")
	draw_list_path_elliptical_arc_to :: proc(self: ^Draw_List, center: Vec2, radius: Vec2, rot: f32, a_min: f32, a_max: f32, num_segments: i32 = 0) ---
	// Cubic Bezier (4 control points)
	@(link_name = "ImDrawList_PathBezierCubicCurveTo")
	draw_list_path_bezier_cubic_curve_to :: proc(self: ^Draw_List, p2: Vec2, p3: Vec2, p4: Vec2, num_segments: i32 = 0) ---
	// Quadratic Bezier (3 control points)
	@(link_name = "ImDrawList_PathBezierQuadraticCurveTo")
	draw_list_path_bezier_quadratic_curve_to :: proc(self: ^Draw_List, p2: Vec2, p3: Vec2, num_segments: i32 = 0) ---
	@(link_name = "ImDrawList_PathRect")
	draw_list_path_rect :: proc(self: ^Draw_List, rect_min: Vec2, rect_max: Vec2, rounding: f32 = 0.0, flags: Draw_Flags = {}) ---
	// Advanced: Draw Callbacks
	// - May be used to alter render state (change sampler, blending, current shader). May be used to emit custom rendering commands (difficult to do correctly, but possible).
	// - Use special ImDrawCallback_ResetRenderState callback to instruct backend to reset its render state to the default.
	// - Your rendering loop must check for 'UserCallback' in ImDrawCmd and call the function instead of rendering triangles. All standard backends are honoring this.
	// - For some backends, the callback may access selected render-states exposed by the backend in a ImGui_ImplXXXX_RenderState structure pointed to by platform_io.Renderer_RenderState.
	// - IMPORTANT: please be mindful of the different level of indirection between using size==0 (copying argument) and using size>0 (copying pointed data into a buffer).
	//   - If userdata_size == 0: we copy/store the 'userdata' argument as-is. It will be available unmodified in ImDrawCmd::UserCallbackData during render.
	//   - If userdata_size > 0,  we copy/store 'userdata_size' bytes pointed to by 'userdata'. We store them in a buffer stored inside the drawlist. ImDrawCmd::UserCallbackData will point inside that buffer so you have to retrieve data from there. Your callback may need to use ImDrawCmd::UserCallbackDataSize if you expect dynamically-sized data.
	//   - Support for userdata_size > 0 was added in v1.91.4, October 2024. So earlier code always only allowed to copy/store a simple void*.
	@(link_name = "ImDrawList_AddCallback")
	draw_list_add_callback :: proc(self: ^Draw_List, callback: Draw_Callback, userdata: rawptr, userdata_size: uint = {}) ---
	// Advanced: Miscellaneous
	// This is useful if you need to forcefully create a new draw call (to allow for dependent rendering / blending). Otherwise primitives are merged into the same draw-call as much as possible
	@(link_name = "ImDrawList_AddDrawCmd")
	draw_list_add_draw_cmd :: proc(self: ^Draw_List) ---
	// Create a clone of the CmdBuffer/IdxBuffer/VtxBuffer.
	@(link_name = "ImDrawList_CloneOutput")
	draw_list_clone_output :: proc(self: ^Draw_List) -> ^Draw_List ---
	// Advanced: Channels
	// - Use to split render into layers. By switching channels to can render out-of-order (e.g. submit FG primitives before BG primitives)
	// - Use to minimize draw calls (e.g. if going back-and-forth between multiple clipping rectangles, prefer to append into separate channels then merge at the end)
	// - This API shouldn't have been in ImDrawList in the first place!
	//   Prefer using your own persistent instance of ImDrawListSplitter as you can stack them.
	//   Using the ImDrawList::ChannelsXXXX you cannot stack a split over another.
	@(link_name = "ImDrawList_ChannelsSplit")
	draw_list_channels_split :: proc(self: ^Draw_List, count: i32) ---
	@(link_name = "ImDrawList_ChannelsMerge")
	draw_list_channels_merge :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList_ChannelsSetCurrent")
	draw_list_channels_set_current :: proc(self: ^Draw_List, n: i32) ---
	// Advanced: Primitives allocations
	// - We render triangles (three vertices)
	// - All primitives needs to be reserved via PrimReserve() beforehand.
	@(link_name = "ImDrawList_PrimReserve")
	draw_list_prim_reserve :: proc(self: ^Draw_List, idx_count: i32, vtx_count: i32) ---
	@(link_name = "ImDrawList_PrimUnreserve")
	draw_list_prim_unreserve :: proc(self: ^Draw_List, idx_count: i32, vtx_count: i32) ---
	// Axis aligned rectangle (composed of two triangles)
	@(link_name = "ImDrawList_PrimRect")
	draw_list_prim_rect :: proc(self: ^Draw_List, a: Vec2, b: Vec2, col: u32) ---
	@(link_name = "ImDrawList_PrimRectUV")
	draw_list_prim_rect_uv :: proc(self: ^Draw_List, a: Vec2, b: Vec2, uv_a: Vec2, uv_b: Vec2, col: u32) ---
	@(link_name = "ImDrawList_PrimQuadUV")
	draw_list_prim_quad_uv :: proc(self: ^Draw_List, a: Vec2, b: Vec2, c: Vec2, d: Vec2, uv_a: Vec2, uv_b: Vec2, uv_c: Vec2, uv_d: Vec2, col: u32) ---
	@(link_name = "ImDrawList_PrimWriteVtx")
	draw_list_prim_write_vtx :: proc(self: ^Draw_List, pos: Vec2, uv: Vec2, col: u32) ---
	@(link_name = "ImDrawList_PrimWriteIdx")
	draw_list_prim_write_idx :: proc(self: ^Draw_List, idx: Draw_Idx) ---
	// Write vertex with unique index
	@(link_name = "ImDrawList_PrimVtx")
	draw_list_prim_vtx :: proc(self: ^Draw_List, pos: Vec2, uv: Vec2, col: u32) ---
	// [Internal helpers]
	@(link_name = "ImDrawList__ResetForNewFrame")
	draw_list_reset_for_new_frame :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList__ClearFreeMemory")
	draw_list_clear_free_memory :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList__PopUnusedDrawCmd")
	draw_list_pop_unused_draw_cmd :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList__TryMergeDrawCmds")
	draw_list_try_merge_draw_cmds :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList__OnChangedClipRect")
	draw_list_on_changed_clip_rect :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList__OnChangedTextureID")
	draw_list_on_changed_texture_id :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList__OnChangedVtxOffset")
	draw_list_on_changed_vtx_offset :: proc(self: ^Draw_List) ---
	@(link_name = "ImDrawList__SetTextureID")
	draw_list_set_texture_id :: proc(self: ^Draw_List, texture_id: Texture_ID) ---
	@(link_name = "ImDrawList__CalcCircleAutoSegmentCount")
	draw_list_calc_circle_auto_segment_count :: proc(self: ^Draw_List, radius: f32) -> i32 ---
	@(link_name = "ImDrawList__PathArcToFastEx")
	draw_list_path_arc_to_fast_ex :: proc(self: ^Draw_List, center: Vec2, radius: f32, a_min_sample: i32, a_max_sample: i32, a_step: i32) ---
	@(link_name = "ImDrawList__PathArcToN")
	draw_list_path_arc_to_n :: proc(self: ^Draw_List, center: Vec2, radius: f32, a_min: f32, a_max: f32, num_segments: i32) ---
	@(link_name = "ImDrawData_Clear")
	draw_data_clear :: proc(self: ^Draw_Data) ---
	// Helper to add an external draw list into an existing ImDrawData.
	@(link_name = "ImDrawData_AddDrawList")
	draw_data_add_draw_list :: proc(self: ^Draw_Data, draw_list: ^Draw_List) ---
	// Helper to convert all buffers from indexed to non-indexed, in case you cannot render indexed. Note: this is slow and most likely a waste of resources. Always prefer indexed rendering!
	@(link_name = "ImDrawData_DeIndexAllBuffers")
	draw_data_de_index_all_buffers :: proc(self: ^Draw_Data) ---
	// Helper to scale the ClipRect field of each ImDrawCmd. Use if your final output buffer is at a different scale than Dear ImGui expects, or if there is a difference between your window resolution and framebuffer resolution.
	@(link_name = "ImDrawData_ScaleClipRects")
	draw_data_scale_clip_rects :: proc(self: ^Draw_Data, fb_scale: Vec2) ---
	@(link_name = "ImFontGlyphRangesBuilder_Clear")
	font_glyph_ranges_builder_clear :: proc(self: ^Font_Glyph_Ranges_Builder) ---
	// Get bit n in the array
	@(link_name = "ImFontGlyphRangesBuilder_GetBit")
	font_glyph_ranges_builder_get_bit :: proc(self: ^Font_Glyph_Ranges_Builder, n: uint) -> bool ---
	// Set bit n in the array
	@(link_name = "ImFontGlyphRangesBuilder_SetBit")
	font_glyph_ranges_builder_set_bit :: proc(self: ^Font_Glyph_Ranges_Builder, n: uint) ---
	// Add character
	@(link_name = "ImFontGlyphRangesBuilder_AddChar")
	font_glyph_ranges_builder_add_char :: proc(self: ^Font_Glyph_Ranges_Builder, c: Wchar) ---
	// Add string (each character of the UTF-8 string are added)
	@(link_name = "ImFontGlyphRangesBuilder_AddText")
	font_glyph_ranges_builder_add_text :: proc(self: ^Font_Glyph_Ranges_Builder, text: cstring, text_end: cstring = nil) ---
	// Add ranges, e.g. builder.AddRanges(ImFontAtlas::GetGlyphRangesDefault()) to force add all of ASCII/Latin+Ext
	@(link_name = "ImFontGlyphRangesBuilder_AddRanges")
	font_glyph_ranges_builder_add_ranges :: proc(self: ^Font_Glyph_Ranges_Builder, ranges: ^Wchar) ---
	// Output new ranges (ImVector_Construct()/ImVector_Destruct() can be used to safely construct out_ranges)
	@(link_name = "ImFontGlyphRangesBuilder_BuildRanges")
	font_glyph_ranges_builder_build_ranges :: proc(self: ^Font_Glyph_Ranges_Builder, out_ranges: ^Vector_Wchar) ---
	@(link_name = "ImFontAtlasCustomRect_IsPacked")
	font_atlas_custom_rect_is_packed :: proc(self: ^Font_Atlas_Custom_Rect) -> bool ---
	@(link_name = "ImFontAtlas_AddFont")
	font_atlas_add_font :: proc(self: ^Font_Atlas, font_cfg: ^Font_Config) -> ^Font ---
	@(link_name = "ImFontAtlas_AddFontDefault")
	font_atlas_add_font_default :: proc(self: ^Font_Atlas, font_cfg: ^Font_Config = nil) -> ^Font ---
	@(link_name = "ImFontAtlas_AddFontFromFileTTF")
	font_atlas_add_font_from_file_ttf :: proc(self: ^Font_Atlas, filename: cstring, size_pixels: f32, font_cfg: ^Font_Config = nil, glyph_ranges: ^Wchar = nil) -> ^Font ---
	// Note: Transfer ownership of 'ttf_data' to ImFontAtlas! Will be deleted after destruction of the atlas. Set font_cfg->FontDataOwnedByAtlas=false to keep ownership of your data and it won't be freed.
	@(link_name = "ImFontAtlas_AddFontFromMemoryTTF")
	font_atlas_add_font_from_memory_ttf :: proc(self: ^Font_Atlas, font_data: rawptr, font_data_size: i32, size_pixels: f32, font_cfg: ^Font_Config = nil, glyph_ranges: ^Wchar = nil) -> ^Font ---
	// 'compressed_font_data' still owned by caller. Compress with binary_to_compressed_c.cpp.
	@(link_name = "ImFontAtlas_AddFontFromMemoryCompressedTTF")
	font_atlas_add_font_from_memory_compressed_ttf :: proc(self: ^Font_Atlas, compressed_font_data: rawptr, compressed_font_data_size: i32, size_pixels: f32, font_cfg: ^Font_Config = nil, glyph_ranges: ^Wchar = nil) -> ^Font ---
	// 'compressed_font_data_base85' still owned by caller. Compress with binary_to_compressed_c.cpp with -base85 parameter.
	@(link_name = "ImFontAtlas_AddFontFromMemoryCompressedBase85TTF")
	font_atlas_add_font_from_memory_compressed_base85ttf :: proc(self: ^Font_Atlas, compressed_font_data_base85: cstring, size_pixels: f32, font_cfg: ^Font_Config = nil, glyph_ranges: ^Wchar = nil) -> ^Font ---
	// Clear input data (all ImFontConfig structures including sizes, TTF data, glyph ranges, etc.) = all the data used to build the texture and fonts.
	@(link_name = "ImFontAtlas_ClearInputData")
	font_atlas_clear_input_data :: proc(self: ^Font_Atlas) ---
	// Clear input+output font data (same as ClearInputData() + glyphs storage, UV coordinates).
	@(link_name = "ImFontAtlas_ClearFonts")
	font_atlas_clear_fonts :: proc(self: ^Font_Atlas) ---
	// Clear output texture data (CPU side). Saves RAM once the texture has been copied to graphics memory.
	@(link_name = "ImFontAtlas_ClearTexData")
	font_atlas_clear_tex_data :: proc(self: ^Font_Atlas) ---
	// Clear all input and output.
	@(link_name = "ImFontAtlas_Clear")
	font_atlas_clear :: proc(self: ^Font_Atlas) ---
	// Build atlas, retrieve pixel data.
	// User is in charge of copying the pixels into graphics memory (e.g. create a texture with your engine). Then store your texture handle with SetTexID().
	// The pitch is always = Width * BytesPerPixels (1 or 4)
	// Building in RGBA32 format is provided for convenience and compatibility, but note that unless you manually manipulate or copy color data into
	// the texture (e.g. when using the AddCustomRect*** api), then the RGB pixels emitted will always be white (~75% of memory/bandwidth waste.
	// Build pixels data. This is called automatically for you by the GetTexData*** functions.
	@(link_name = "ImFontAtlas_Build")
	font_atlas_build :: proc(self: ^Font_Atlas) -> bool ---
	// 1 byte per-pixel
	@(link_name = "ImFontAtlas_GetTexDataAsAlpha8")
	font_atlas_get_tex_data_as_alpha8 :: proc(self: ^Font_Atlas, out_pixels: ^^u8, out_width: ^i32, out_height: ^i32, out_bytes_per_pixel: ^i32 = nil) ---
	// 4 bytes-per-pixel
	@(link_name = "ImFontAtlas_GetTexDataAsRGBA32")
	font_atlas_get_tex_data_as_rgba32 :: proc(self: ^Font_Atlas, out_pixels: ^^u8, out_width: ^i32, out_height: ^i32, out_bytes_per_pixel: ^i32 = nil) ---
	// Bit ambiguous: used to detect when user didn't build texture but effectively we should check TexID != 0 except that would be backend dependent...
	@(link_name = "ImFontAtlas_IsBuilt")
	font_atlas_is_built :: proc(self: ^Font_Atlas) -> bool ---
	@(link_name = "ImFontAtlas_SetTexID")
	font_atlas_set_tex_id :: proc(self: ^Font_Atlas, id: Texture_ID) ---
	// Helpers to retrieve list of common Unicode ranges (2 value per range, values are inclusive, zero-terminated list)
	// NB: Make sure that your string are UTF-8 and NOT in your local code page.
	// Read https://github.com/ocornut/imgui/blob/master/docs/FONTS.md/#about-utf-8-encoding for details.
	// NB: Consider using ImFontGlyphRangesBuilder to build glyph ranges from textual data.
	// Basic Latin, Extended Latin
	@(link_name = "ImFontAtlas_GetGlyphRangesDefault")
	font_atlas_get_glyph_ranges_default :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + Greek and Coptic
	@(link_name = "ImFontAtlas_GetGlyphRangesGreek")
	font_atlas_get_glyph_ranges_greek :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + Korean characters
	@(link_name = "ImFontAtlas_GetGlyphRangesKorean")
	font_atlas_get_glyph_ranges_korean :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + Hiragana, Katakana, Half-Width, Selection of 2999 Ideographs
	@(link_name = "ImFontAtlas_GetGlyphRangesJapanese")
	font_atlas_get_glyph_ranges_japanese :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + Half-Width + Japanese Hiragana/Katakana + full set of about 21000 CJK Unified Ideographs
	@(link_name = "ImFontAtlas_GetGlyphRangesChineseFull")
	font_atlas_get_glyph_ranges_chinese_full :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + Half-Width + Japanese Hiragana/Katakana + set of 2500 CJK Unified Ideographs for common simplified Chinese
	@(link_name = "ImFontAtlas_GetGlyphRangesChineseSimplifiedCommon")
	font_atlas_get_glyph_ranges_chinese_simplified_common :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + about 400 Cyrillic characters
	@(link_name = "ImFontAtlas_GetGlyphRangesCyrillic")
	font_atlas_get_glyph_ranges_cyrillic :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + Thai characters
	@(link_name = "ImFontAtlas_GetGlyphRangesThai")
	font_atlas_get_glyph_ranges_thai :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// Default + Vietnamese characters
	@(link_name = "ImFontAtlas_GetGlyphRangesVietnamese")
	font_atlas_get_glyph_ranges_vietnamese :: proc(self: ^Font_Atlas) -> ^Wchar ---
	// You can request arbitrary rectangles to be packed into the atlas, for your own purposes.
	// - After calling Build(), you can query the rectangle position and render your pixels.
	// - If you render colored output, set 'atlas->TexPixelsUseColors = true' as this may help some backends decide of preferred texture format.
	// - You can also request your rectangles to be mapped as font glyph (given a font + Unicode point),
	//   so you can render e.g. custom colorful icons and use them as regular glyphs.
	// - Read docs/FONTS.md for more details about using colorful icons.
	// - Note: this API may be redesigned later in order to support multi-monitor varying DPI settings.
	@(link_name = "ImFontAtlas_AddCustomRectRegular")
	font_atlas_add_custom_rect_regular :: proc(self: ^Font_Atlas, width: i32, height: i32) -> i32 ---
	@(link_name = "ImFontAtlas_AddCustomRectFontGlyph")
	font_atlas_add_custom_rect_font_glyph :: proc(self: ^Font_Atlas, font: ^Font, id: Wchar, width: i32, height: i32, advance_x: f32, offset: Vec2 = Vec2{0, 0}) -> i32 ---
	@(link_name = "ImFontAtlas_GetCustomRectByIndex")
	font_atlas_get_custom_rect_by_index :: proc(self: ^Font_Atlas, index: i32) -> ^Font_Atlas_Custom_Rect ---
	// [Internal]
	@(link_name = "ImFontAtlas_CalcCustomRectUV")
	font_atlas_calc_custom_rect_uv :: proc(self: ^Font_Atlas, rect: ^Font_Atlas_Custom_Rect, out_uv_min: ^Vec2, out_uv_max: ^Vec2) ---
	@(link_name = "ImFont_FindGlyph")
	font_find_glyph :: proc(self: ^Font, c: Wchar) -> ^Font_Glyph ---
	@(link_name = "ImFont_FindGlyphNoFallback")
	font_find_glyph_no_fallback :: proc(self: ^Font, c: Wchar) -> ^Font_Glyph ---
	@(link_name = "ImFont_GetCharAdvance")
	font_get_char_advance :: proc(self: ^Font, c: Wchar) -> f32 ---
	@(link_name = "ImFont_IsLoaded")
	font_is_loaded :: proc(self: ^Font) -> bool ---
	@(link_name = "ImFont_GetDebugName")
	font_get_debug_name :: proc(self: ^Font) -> cstring ---
	// [Internal] Don't use!
	// 'max_width' stops rendering after a certain width (could be turned into a 2d size). FLT_MAX to disable.
	// 'wrap_width' enable automatic word-wrapping across multiple lines to fit into given width. 0.0f to disable.
	// utf8
	@(link_name = "ImFont_CalcTextSizeA")
	font_calc_text_size_a :: proc(self: ^Font, size: f32, max_width: f32, wrap_width: f32, text_begin: cstring, text_end: cstring = nil, remaining: ^cstring = nil) -> Vec2 ---
	@(link_name = "ImFont_CalcWordWrapPositionA")
	font_calc_word_wrap_position_a :: proc(self: ^Font, scale: f32, text: cstring, text_end: cstring, wrap_width: f32) -> cstring ---
	@(link_name = "ImFont_RenderChar")
	font_render_char :: proc(self: ^Font, draw_list: ^Draw_List, size: f32, pos: Vec2, col: u32, c: Wchar) ---
	@(link_name = "ImFont_RenderText")
	font_render_text :: proc(self: ^Font, draw_list: ^Draw_List, size: f32, pos: Vec2, col: u32, clip_rect: Vec4, text_begin: cstring, text_end: cstring, wrap_width: f32 = 0.0, cpu_fine_clip: bool = false) ---
	// [Internal] Don't use!
	@(link_name = "ImFont_BuildLookupTable")
	font_build_lookup_table :: proc(self: ^Font) ---
	@(link_name = "ImFont_ClearOutputData")
	font_clear_output_data :: proc(self: ^Font) ---
	@(link_name = "ImFont_GrowIndex")
	font_grow_index :: proc(self: ^Font, new_size: i32) ---
	@(link_name = "ImFont_AddGlyph")
	font_add_glyph :: proc(self: ^Font, src_cfg: ^Font_Config, c: Wchar, x0: f32, y0: f32, x1: f32, y1: f32, u0: f32, v0: f32, u1: f32, v1: f32, advance_x: f32) ---
	// Makes 'dst' character/glyph points to 'src' character/glyph. Currently needs to be called AFTER fonts have been built.
	@(link_name = "ImFont_AddRemapChar")
	font_add_remap_char :: proc(self: ^Font, dst: Wchar, src: Wchar, overwrite_dst: bool = true) ---
	@(link_name = "ImFont_IsGlyphRangeUnused")
	font_is_glyph_range_unused :: proc(self: ^Font, c_begin: u32, c_last: u32) -> bool ---
	// Helpers
	@(link_name = "ImGuiViewport_GetCenter")
	viewport_get_center :: proc(self: ^Viewport) -> Vec2 ---
	@(link_name = "ImGuiViewport_GetWorkCenter")
	viewport_get_work_center :: proc(self: ^Viewport) -> Vec2 ---
}
