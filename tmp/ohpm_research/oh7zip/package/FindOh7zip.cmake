if(NOT OH7ZIP_ROOT_PATH)
    message(FATAL_ERROR "OH7ZIP_ROOT_PATH must be setted up at first.")
endif()

set(OH7ZIP_SEARCH_PATH ${OH7ZIP_ROOT_PATH})
set(CMAKE_CXX_STANDARD 17)
# find base path
find_path(OH7ZIP_PATH
    NAMES include/common.h
    PATHS ${OH7ZIP_SEARCH_PATH}
    CMAKE_FIND_ROOT_PATH_BOTH
    )

# find includes
if(NOT OH7ZIP_INCLUDE_DIRS)
    find_path(OH7ZIP_INCLUDE_DIR
        NAMES common.h
        PATHS ${OH7ZIP_PATH}
        PATH_SUFFIXES include
        CMAKE_FIND_ROOT_PATH_BOTH
    )

    set(OH7ZIP_INCLUDE_DIRS
        ${OH7ZIP_INCLUDE_DIR})
endif()

# find link directories
if(NOT OH7ZIP_LINK_DIRS)
    # OH7ZIP 库文件链接路径
    find_path(OH7ZIP_TMP_LINK_DIRS
        NAMES liboh7zip.so
        PATHS "${OH7ZIP_PATH}"
        PATH_SUFFIXES "libs/${CMAKE_OHOS_ARCH_ABI}"
        CMAKE_FIND_ROOT_PATH_BOTH
    )

    set(OH7ZIP_LINK_DIRS
        ${OH7ZIP_TMP_LINK_DIRS})

endif()

# find librarys
if(NOT OH7ZIP_LIBRARIS)
    # OH7ZIP 库文件
    find_library(OH7ZIP_LIBRARY
        NAMES oh7zip
        PATHS "${OH7ZIP_PATH}"
        PATH_SUFFIXES "libs/${CMAKE_OHOS_ARCH_ABI}"
        CMAKE_FIND_ROOT_PATH_BOTH
    )

    set(OH7ZIP_LIBRARIS
        oh7zip
		)

endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(OH7ZIP DEFAULT_MSG
    OH7ZIP_INCLUDE_DIRS
    OH7ZIP_LIBRARIS
)

if(OH7ZIP_FOUND AND NOT TARGET OH7ZIP::oh7zip)
    # 创建接口lib
    add_library(OH7ZIP::oh7zip INTERFACE IMPORTED)

    # 设置target 头文件依赖
    target_include_directories(OH7ZIP::oh7zip INTERFACE ${OH7ZIP_INCLUDE_DIRS})

    # 设置target link依赖路径
    target_link_directories(OH7ZIP::oh7zip INTERFACE ${OH7ZIP_LINK_DIRS})

    # 设置target lib依赖
    target_link_libraries(OH7ZIP::oh7zip INTERFACE ${OH7ZIP_LIBRARIS})

    # 设置target 编译宏
    target_compile_definitions(OH7ZIP::oh7zip INTERFACE ${OH7ZIP_DEFINITIONS})

    # 安全编译选项 NO Rpath 规则
    set(CMAKE_SKIP_RPATH TRUE)
endif()