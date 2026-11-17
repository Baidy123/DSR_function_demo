# 目标文件名称
TARGET_FILE_NAME = Target

# 编译目录
BUILD_DIR = Build

# Release 编译子目录
SUB_DIR_RELEASE = Release

# Debug 编译子目录
SUB_DIR_DEBUG = Debug

# Release 优化等级
RELEASE_OPT = -Os

# Debug 优化等级
DEBUG_OPT = -O0

# GUI或CUI编译选项 [0]CUI/Console [1]GUI
GUI = 1

# C编译标准
C_STD = c17

# C++编译标准
CXX_STD = c++17

# 源文件编码定义
INPUT_CHAR_ENCODING = UTF-8

# 编译产物单字节字符(char)编码定义
OUTPUT_CHAR_ENCODING = UTF-8

# 编译产物宽字符(wchar_t)编码定义
OUTPUT_WCHAR_ENCODING = UTF-16LE

# 编译工具前缀
COMPLIER_PREFIX =	\

# C编译工具
C_COMPLIER = $(strip $(COMPLIER_PREFIX))gcc

# C++编译工具
CXX_COMPLIER = $(strip $(COMPLIER_PREFIX))g++

# Windows 资源文件编译工具
WIN_RES_COMPLIER = windres

##################################################################################

# 链接库
LIB_LINK = 			\
-lgdi32				\
-luser32			\
-ld3d11				\
-ld3dcompiler		\
-ldxgi				\
-lwinmm				\
-lole32				\
-luuid				\

# C定义
C_DEFS =			\
_UNICODE			\
UNICODE				\

# C头文件目录
C_INCLUDES_PATHS =	\

# C源文件目录
C_SOURCES_PATHS =	\

# C额外单个源文件
C_EXTERA_SOURCES =	\

# C++定义
CXX_DEFS =			\
_UNICODE			\
UNICODE				\

# C++ 头文件目录
CXX_INCLUDES_PATHS = 		\
Components/Shared/Inc		\
Components/Platform/Inc		\
Components/Render/Inc		\
Components/World/Inc		\
Components/Game/Inc			\
Components/Audio/Inc		\

# C++源文件目录
CXX_SOURCES_PATHS = 		\
Components/Main/Src			\
Components/Shared/Src		\
Components/Platform/Src		\
Components/Render/Src		\
Components/World/Src		\
Components/Game/Src			\
Components/Audio/Src		\

# C++额外单个源文件
CXX_EXTERA_SOURCES = 	\

# Windows 资源文件脚本头文件路径
WIN_RESOURCE_INCLUDES_PATHS = 	\

# Windows 资源文件脚本列表
WIN_RESOURCE_SCRIPTS = Resources/Resources.rc

##################################################################################

# C编译选项
CFLAGS = $(foreach text,$(C_DEFS),$(addprefix -D,$(text)))				\
		 $(foreach path,$(C_INCLUDES_PATHS),$(addprefix -I,$(path))) 	\
		-std=$(strip $(C_STD))											\
		-finput-charset=$(strip $(INPUT_CHAR_ENCODING)) 				\
		-fexec-charset=$(strip $(OUTPUT_CHAR_ENCODING)) 				\
		-fwide-exec-charset=$(strip $(OUTPUT_WCHAR_ENCODING))			\
		-static 														\
		-Wall 															\
		-MMD -MP -MF"$(@:%.o=%.d)"										\

# C++编译选项
CXXFLAGS = $(foreach text,$(CXX_DEFS),$(addprefix -D,$(text)))				\
		   $(foreach path,$(CXX_INCLUDES_PATHS),$(addprefix -I,$(path))) 	\
		  -std=$(strip $(CXX_STD))											\
		  -finput-charset=$(strip $(INPUT_CHAR_ENCODING)) 					\
		  -fexec-charset=$(strip $(OUTPUT_CHAR_ENCODING)) 					\
		  -fwide-exec-charset=$(strip $(OUTPUT_WCHAR_ENCODING))				\
		  -static 															\
		  -Wall 															\
		  -MMD -MP -MF"$(@:%.o=%.d)"										\


# 链接选项
LDFLAGS = -Wl,-Map,$(basename $@).map \

##################################################################################

# GUI与CUI选项附加
ifeq ($(GUI), 1)
LDFLAGS  += -mwindows
else
LDFLAGS  += -mconsole
endif

# C目标文件及索引目录关联
OBJECTS  = $(notdir $(C_EXTERA_SOURCES:.c=.o))
OBJECTS += $(subst .c,.o,$(notdir $(foreach path,$(C_SOURCES_PATHS),$(wildcard $(path)/*.c))))
vpath %.c $(sort $(dir $(C_EXTERA_SOURCES))) $(sort $(C_SOURCES_PATHS))

# C++目标文件及索引目录关联
OBJECTS += $(notdir $(CXX_EXTERA_SOURCES:.cpp=.o))
OBJECTS += $(subst .cpp,.o,$(notdir $(foreach path,$(CXX_SOURCES_PATHS),$(wildcard $(path)/*.cpp))))
vpath %.cpp $(sort $(dir $(CXX_EXTERA_SOURCES))) $(sort $(CXX_SOURCES_PATHS))

# Windows资源文件及索引目录关联
OBJECTS += $(notdir $(WIN_RESOURCE_SCRIPTS:.rc=.o))
vpath %.rc $(sort $(dir $(WIN_RESOURCE_SCRIPTS)))


# Release 目标文件
RELEASE_OBJECTS = $(addprefix $(BUILD_DIR)/$(SUB_DIR_RELEASE)/,$(OBJECTS))

# Debug 目标文件
DEBUG_OBJECTS = $(addprefix $(BUILD_DIR)/$(SUB_DIR_DEBUG)/,$(OBJECTS))

##################################################################################

# all任务 目标为 release 和 debug 产物
all: $(BUILD_DIR)/$(SUB_DIR_RELEASE)/$(TARGET_FILE_NAME).exe $(BUILD_DIR)/$(SUB_DIR_DEBUG)/$(TARGET_FILE_NAME).exe
	@echo ====== [All] Build Procedure Accomplished ======

# release任务 目标为 release 产物 
release: $(BUILD_DIR)/$(SUB_DIR_RELEASE)/$(TARGET_FILE_NAME).exe
	@echo ====== [Release] Build Procedure Accomplished ======

# debug任务 目标为 debug 产物
debug: $(BUILD_DIR)/$(SUB_DIR_DEBUG)/$(TARGET_FILE_NAME).exe
	@echo ====== [Debug] Build Procedure Accomplished ====== 

# 清理任务
clean: $(BUILD_DIR)
	powershell rm -r $(BUILD_DIR)

# 构建目录生成
$(BUILD_DIR):
	powershell mkdir $@

# Release 工作目录生成
$(BUILD_DIR)/$(SUB_DIR_RELEASE): | $(BUILD_DIR)
	powershell mkdir $@

# Debug 工作目录生成
$(BUILD_DIR)/$(SUB_DIR_DEBUG): | $(BUILD_DIR)
	powershell mkdir $@

# Release 最终可执行文件编译任务
$(BUILD_DIR)/$(SUB_DIR_RELEASE)/$(TARGET_FILE_NAME).exe: $(RELEASE_OBJECTS)
	@echo ====== [Release] All File Compiled. Now Linking... ====== 
	$(CXX_COMPLIER) $(RELEASE_OBJECTS) -static -s -o $@ $(LIB_LINK) $(LDFLAGS)
	@echo ====== [Release] Program Link Finished ======

# Debug 最终可执行文件编译任务
$(BUILD_DIR)/$(SUB_DIR_DEBUG)/$(TARGET_FILE_NAME).exe: $(DEBUG_OBJECTS)
	@echo ====== [Debug] All File Compiled. Now Linking... ====== 
	$(CXX_COMPLIER) $(DEBUG_OBJECTS) -static -o $@ $(LIB_LINK) $(LDFLAGS)
	@echo ====== [Debug] Program Link Finished ====== 

# C Release 目标文件编译
$(BUILD_DIR)/$(SUB_DIR_RELEASE)/%.o: %.c Makefile | $(BUILD_DIR)/$(SUB_DIR_RELEASE)
	@echo ====== [Release] C Source File "$<" Compiling... ======
	$(C_COMPLIER) -c $(CFLAGS) $(RELEASE_OPT) -Wa,-a,-ad,-alms=$(BUILD_DIR)/$(SUB_DIR_RELEASE)/$(notdir $(<:.c=.lst)) $< -o $@

# C++ Release 目标文件编译
$(BUILD_DIR)/$(SUB_DIR_RELEASE)/%.o: %.cpp Makefile | $(BUILD_DIR)/$(SUB_DIR_RELEASE)
	@echo ====== [Release] C++ Source File "$<" Compiling... ====== 
	$(CXX_COMPLIER) -c $(CXXFLAGS) $(RELEASE_OPT) -Wa,-a,-ad,-ahlms=$(BUILD_DIR)/$(SUB_DIR_RELEASE)/$(notdir $(<:.cpp=.lst)) $< -o $@

# Release 资源脚本文件编译
$(BUILD_DIR)/$(SUB_DIR_RELEASE)/%.o: %.rc Resources/ArtPack.bin Makefile | $(BUILD_DIR)/$(SUB_DIR_RELEASE)
	@echo ====== [Release] Windows Resource Script File "$<" Compiling... ====== 
	$(WIN_RES_COMPLIER) $(foreach path,$(WIN_RESOURCE_INCLUDES_PATHS),$(addprefix -I,$(path))) $< -o $@

# C Debug 目标文件编译
$(BUILD_DIR)/$(SUB_DIR_DEBUG)/%.o: %.c Makefile | $(BUILD_DIR)/$(SUB_DIR_DEBUG)
	@echo ====== [Debug] C Source File "$<" Compiling... ======
	$(C_COMPLIER) -c $(CFLAGS) $(DEBUG_OPT) -g -Wa,-a,-ad,-alms=$(BUILD_DIR)/$(SUB_DIR_DEBUG)/$(notdir $(<:.c=.lst)) $< -o $@

# C++ Debug 目标文件编译
$(BUILD_DIR)/$(SUB_DIR_DEBUG)/%.o: %.cpp Makefile | $(BUILD_DIR)/$(SUB_DIR_DEBUG)
	@echo ====== [Debug] C++ Source File "$<" Compiling... ====== 
	$(CXX_COMPLIER) -c $(CXXFLAGS) $(DEBUG_OPT) -g -Wa,-a,-ad,-ahlms=$(BUILD_DIR)/$(SUB_DIR_DEBUG)/$(notdir $(<:.cpp=.lst)) $< -o $@

# Debug 资源脚本文件编译
$(BUILD_DIR)/$(SUB_DIR_DEBUG)/%.o: %.rc Resources/ArtPack.bin Makefile | $(BUILD_DIR)/$(SUB_DIR_DEBUG)
	@echo ====== [Debug] Windows Resource Script File "$<" Compiling... ====== 
	$(WIN_RES_COMPLIER) $(foreach path,$(WIN_RESOURCE_INCLUDES_PATHS),$(addprefix -I,$(path))) $< -o $@


# 依赖关系
-include $(RELEASE_OBJECTS:.o=.d)
-include $(DEBUG_OBJECTS:.o=.d)