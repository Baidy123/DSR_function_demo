# 测试工具独立构建入口；不参与最终游戏产物。
# 用法（在项目根目录）：
#   make -C Tools
#   make -C Tools unit
#   make -C Tools offscreen

CXX = g++
CXX_STD = c++17

COMPONENTS = ../Components
INCLUDES = -I$(COMPONENTS)/Shared/Inc \
           -I$(COMPONENTS)/Platform/Inc \
           -I$(COMPONENTS)/Render/Inc \
           -I$(COMPONENTS)/World/Inc \
           -I$(COMPONENTS)/Game/Inc \
           -I$(COMPONENTS)/Audio/Inc \
           -IUnitTests/Inc \
           -IOffscreenTest/Inc

CXXFLAGS = -std=$(CXX_STD) -finput-charset=UTF-8 -fexec-charset=UTF-8 \
           -fwide-exec-charset=UTF-16LE -static -Wall -O2 $(INCLUDES)

LIBS = -lgdi32 -luser32 -ld3d11 -ld3dcompiler -ldxgi -lwinmm -lole32 -luuid

UNIT_DIR = UnitTests/Build
OFFSCREEN_DIR = OffscreenTest/Build

UNIT_TARGET = $(UNIT_DIR)/UnitTests.exe
OFFSCREEN_TARGET = $(OFFSCREEN_DIR)/OffscreenTest.exe

UNIT_SOURCES = \
    UnitTests/Src/UnitTests_Main.cpp \
    $(COMPONENTS)/Shared/Src/Shared_Math.cpp \
    $(COMPONENTS)/Shared/Src/Shared_String.cpp \
    $(COMPONENTS)/Shared/Src/Shared_Log.cpp \
    $(COMPONENTS)/Game/Src/Game_Inventory.cpp \
    $(COMPONENTS)/Game/Src/Game_Quest.cpp \
    $(COMPONENTS)/Game/Src/Game_Dialogue.cpp \
    $(COMPONENTS)/Game/Src/Game_Story.cpp \
    $(COMPONENTS)/World/Src/World_Collision.cpp

OFFSCREEN_SOURCES = \
    OffscreenTest/Src/OffscreenTest_Main.cpp \
    $(filter-out $(COMPONENTS)/Main/Src/Main_Entry.cpp,$(wildcard $(COMPONENTS)/*/Src/*.cpp))

all: unit offscreen
	@echo ====== [Tools] All Tools Built ======

unit: $(UNIT_TARGET)

offscreen: $(OFFSCREEN_TARGET)

$(UNIT_TARGET): $(UNIT_SOURCES) | $(UNIT_DIR)
	$(CXX) $(CXXFLAGS) $(UNIT_SOURCES) -o $@ -mconsole $(LIBS)

$(OFFSCREEN_TARGET): $(OFFSCREEN_SOURCES) | $(OFFSCREEN_DIR)
	$(CXX) $(CXXFLAGS) $(OFFSCREEN_SOURCES) -o $@ -mconsole $(LIBS)

$(UNIT_DIR):
	powershell mkdir $@

$(OFFSCREEN_DIR):
	powershell mkdir $@

clean:
	powershell rm -r $(UNIT_DIR),$(OFFSCREEN_DIR) -ErrorAction SilentlyContinue

.PHONY: all unit offscreen clean
