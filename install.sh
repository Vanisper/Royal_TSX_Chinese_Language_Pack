#!/bin/bash

# 设置已验证的最大版本号和最小支持版本号
readonly verified_max_support_version="6.4.1"
readonly min_support_version="4.3.6"

# 获取当前脚本运行目录并切换到工作目录
base_path=$(cd "$(dirname "$0")" || exit; pwd)
cd "$base_path" || exit

# 获取主程序安装路径
main_app_path=""
if [ -d "/Applications/Royal TSX.app" ]; then
    main_app_path="/Applications/Royal TSX.app"
elif [ -d "$HOME/Applications/Royal TSX.app" ]; then
    main_app_path="$HOME/Applications/Royal TSX.app"
else
    echo -e "\033[31m主程序未安装!\033[0m"
    exit 1
fi

# 获取主程序版本号
get_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"
}

# 比较版本号
# 返回值:
#   -1: $1 < $2
#    0: $1 = $2
#    1: $1 > $2
compare_versions() {
    local left="$1"
    local right="$2"
    local IFS=.
    local i
    local left_len
    local right_len
    local max_len
    local -a left_parts=($left)
    local -a right_parts=($right)

    left_len=${#left_parts[@]}
    right_len=${#right_parts[@]}
    max_len=$left_len
    if (( right_len > max_len )); then
        max_len=$right_len
    fi

    for ((i = 0; i < max_len; i++)); do
        local left_value="${left_parts[i]:-0}"
        local right_value="${right_parts[i]:-0}"

        if (( 10#$left_value > 10#$right_value )); then
            echo "1"
            return
        fi

        if (( 10#$left_value < 10#$right_value )); then
            echo "-1"
            return
        fi
    done

    echo "0"
}

# 检查主程序版本是否在支持范围内
check_version() {
    local current_version="$1"
    local min_version="$2"
    local max_version="$3"
    local min_result
    local max_result

    min_result=$(compare_versions "$current_version" "$min_version")
    max_result=$(compare_versions "$current_version" "$max_version")

    if [[ "$min_result" == "-1" ]]; then
        echo -e "\033[31m主程序版本不匹配，本程序支持的最小版本号为:${min_version}，当前安装的版本为:${current_version}!\033[0m"
        exit 1
    fi

    if [[ "$max_result" == "1" ]]; then
        echo -e "\033[33m当前安装的版本为:${current_version}，高于已验证版本:${max_version}。将根据检测到的实际目录结构继续尝试汉化。\033[0m"
        return
    fi

    echo "主程序版本匹配，当前安装的版本为:${current_version}"
}

# 查找应用内的资源目录
find_resource_dir() {
    local bundle_path="$1"
    local resource_name="$2"

    find "$bundle_path/Contents" -type d -path "*/Resources/$resource_name" -print -quit 2>/dev/null
}

# 查找与当前版本匹配的本地资源目录
find_versioned_source_dir() {
    local base_name="$1"
    local current_version="$2"

    find . -maxdepth 1 -type d -name "${base_name}-${current_version}*" -print | sed 's#^\./##' | sort -V | tail -n 1
}

# 复制目录内容
copy_tree_contents() {
    local source_dir="$1"
    local target_dir="$2"

    if [ ! -d "$source_dir" ]; then
        echo -e "\033[33m未找到源目录:${source_dir}\033[0m"
        return 1
    fi

    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir" || return 1
    fi

    cp -R "$source_dir/." "$target_dir/"
}

# 复制单个文件
copy_file() {
    local source_file="$1"
    local target_file="$2"

    if [ ! -f "$source_file" ]; then
        echo -e "\033[33m未找到源文件:${source_file}\033[0m"
        return 1
    fi

    mkdir -p "$(dirname "$target_file")" || return 1
    cp "$source_file" "$target_file"
}

# 汉化主程序
translate_main_app() {
    local target_dir="$1/Contents/Resources/zh_Hans.lproj"

    if copy_tree_contents "Main Application/zh_Hans.lproj" "$target_dir"; then
        echo "主程序汉化完成!"
    else
        echo -e "\033[31m主程序汉化失败!\033[0m"
    fi
}

# 汉化插件
translate_plugins() {
    local plugin_list=("$@")
    echo "目前共有${#plugin_list[@]}个插件支持汉化，开始检查并汉化，请留意后续汉化进度。"
    for plugin in "${plugin_list[@]}"; do
        # 获取 UUID 和名称
        uuid=$(echo "${plugin}" | cut -d':' -f1)
        name=$(echo "${plugin}" | cut -d':' -f2)
        source_dir="$plugin_source_root/$uuid.plugin"
        target_dir="$HOME/Library/Application Support/Royal TSX/Plugins/Installed/$uuid.plugin"

        if [ ! -d "$target_dir" ]; then
            echo -e "\033[33m${name}插件未安装!\033[0m"
        elif [ ! -d "$source_dir" ]; then
            echo -e "\033[33m未找到${name}插件的汉化资源，已跳过!\033[0m"
        else
            local success=1
            local copied=0

            while IFS= read -r zh_dir; do
                local relative_dir="${zh_dir#$source_dir/}"
                if copy_tree_contents "$zh_dir" "$target_dir/$relative_dir"; then
                    copied=1
                else
                    success=0
                    break
                fi
            done < <(find "$source_dir" -type d -name "zh_Hans.lproj" | sort)

            if [ "$success" -eq 1 ] && [ -f "$source_dir/PluginInfo/PluginInfo.xml" ]; then
                if copy_file "$source_dir/PluginInfo/PluginInfo.xml" "$target_dir/PluginInfo/PluginInfo.xml"; then
                    copied=1
                else
                    success=0
                fi
            fi

            if [ "$success" -eq 1 ] && [ "$copied" -eq 1 ]; then
                echo "${name}插件汉化完成!"
            elif [ "$success" -eq 1 ]; then
                echo -e "\033[33m未找到${name}插件可复制的汉化文件，已跳过!\033[0m"
            else
                echo -e "\033[31m${name}插件汉化失败!\033[0m"
            fi
        fi
    done
}

# 汉化插件中心
translate_plugin_gallery() {
    local source_dir="$1"
    local target_dir="$2"
    local success=1
    local copied=0

    if [ -z "$target_dir" ]; then
        echo -e "\033[33m未检测到插件中心目录，已跳过插件中心汉化。\033[0m"
        return
    fi

    if [ -f "$source_dir/index.html" ]; then
        if copy_file "$source_dir/index.html" "$target_dir/index.html"; then
            copied=1
        else
            success=0
        fi
    fi

    if [ "$success" -eq 1 ] && [ -f "$source_dir/js/language_cn.js" ]; then
        if copy_file "$source_dir/js/language_cn.js" "$target_dir/js/language_cn.js"; then
            copied=1
        else
            success=0
        fi
    fi

    if [ "$success" -eq 1 ] && [ -f "$source_dir/cn.lproj/Localizable.strings.js" ]; then
        if copy_file "$source_dir/cn.lproj/Localizable.strings.js" "$target_dir/cn.lproj/Localizable.strings.js"; then
            copied=1
        else
            success=0
        fi
    fi

    if [ "$success" -eq 1 ] && [ "$copied" -eq 1 ]; then
        echo "插件中心汉化完成!"
    elif [ "$success" -eq 1 ]; then
        echo -e "\033[33m未找到插件中心可复制的汉化文件，已跳过插件中心汉化。\033[0m"
    else
        echo -e "\033[31m插件中心汉化失败!\033[0m"
    fi
}

# 汉化入门简介
translate_getting_started() {
    local target_dir="$1"

    if [ -z "$target_dir" ]; then
        echo -e "\033[33m未检测到 GettingStarted 目录，已跳过入门简介汉化。\033[0m"
        return
    fi

    if copy_file "GettingStarted/index.htm" "$target_dir/index.htm"; then
        echo "入门简介汉化完成!"
    else
        echo -e "\033[31m入门简介汉化失败!\033[0m"
    fi
}

version=$(get_version "$main_app_path")

check_version "$version" "$min_support_version" "$verified_max_support_version"

plugin_gallery_target=$(find_resource_dir "$main_app_path" "PluginGallery")
getting_started_target=$(find_resource_dir "$main_app_path" "GettingStarted")
plugin_gallery_source="PluginGallery"
plugin_source_root="Plugins"
versioned_plugin_gallery_source=$(find_versioned_source_dir "PluginGallery" "$version")
versioned_plugin_source_root=$(find_versioned_source_dir "Plugins" "$version")

if [[ "$plugin_gallery_target" == *"RoyalTSXNativeUI.framework"* ]]; then
    plugin_gallery_source="PluginGallery-6.x"
fi

if [ -n "$versioned_plugin_gallery_source" ]; then
    plugin_gallery_source="$versioned_plugin_gallery_source"
fi

if [ -n "$versioned_plugin_source_root" ]; then
    plugin_source_root="$versioned_plugin_source_root"
fi

# 插件列表
plugins=(
    # FreeRDPPlugin.framework
    "1c919170-3ee3-437f-9326-a2316a9293a0:RDP"
    # FileTransferPlugin.framework
    "3e63afa6-61f6-4f9f-85bf-a773ab0408b0:File Transfer"
    # WebConnectionPlugin.framework
    "4a376bc0-9c23-11e1-a8b0-0800200c9a66:Web (based on WebKit)"
    # WindowsEventsPlugin.framework
    "6b941bae-bff5-46a3-8a40-91ca66c54c89:Windows Events View"
    # iTermPlugin.framework
    "7c84a650-9896-11e1-a8b0-0800200c9a66:Terminal (based on iTerm2)"
    # VMwarePlugin.framework
    "9e13c958-7515-4ddd-b914-e00f77dd609b:VMware"
    # PowerShellPlugin.framework
    "21e6e2a4-50e7-49a9-a1b9-56e2eb6f9640:PowerShell"
    # RoyalVNCPlugin.framework
    "50ee9d0f-4335-4c1d-8197-b2608a07e301:VNC (based on RoyalVNC)"
    # HyperVPlugin.framework
    "651a0888-d654-4d6e-b3c5-355fc392f3c9:Hyper-V"
    # WindowsServicesPlugin.framework
    "49253779-c4b7-43c0-bf33-0654f1589481:Windows Services"
    # TeamViewerPlugin.framework
    "53945263-2109-409b-b682-90c282be9b58:TeamViewer"
    # WindowsProcessesPlugin.framework
    "b395595d-c20f-49b6-87a0-375d8d8b052c:Windows Processes"
    # ScreenSharingPlugin.framework
    "c96b0f90-98be-456e-acc6-b9ee3896ffb5:VNC (based on Apple Screen Sharing)"
    # ChickenPlugin.framework
    "dfd69050-9897-11e1-a8b0-0800200c9a66:VNC (based on Chicken)"
    # TerminalServicesPlugin.framework
    "ecda13f4-a5b5-4791-a027-b947008c943f:Terminal Services"
)

# 汉化主程序
translate_main_app "$main_app_path"
# 汉化插件中心及其它
translate_plugin_gallery "$plugin_gallery_source" "$plugin_gallery_target"
# 汉化入门简介
translate_getting_started "$getting_started_target"
# 汉化插件
translate_plugins "${plugins[@]}"
