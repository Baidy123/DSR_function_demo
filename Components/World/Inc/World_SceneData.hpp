#ifndef __WORLD_SCENEDATA_HPP__
#define __WORLD_SCENEDATA_HPP__

#include "World_Types.hpp"

namespace fc {

/**
 * @brief 构建“余烬酒吧外”场景蓝本。
 * @return 场景定义。
 */
SceneDefinition BuildBarExteriorScene();

/**
 * @brief 构建“余烬酒吧内”场景蓝本。
 * @return 场景定义。
 */
SceneDefinition BuildBarInteriorScene();

/**
 * @brief 构建“铁港仓库”场景蓝本。
 * @return 场景定义。
 */
SceneDefinition BuildIronHarborScene();

/**
 * @brief 按场景 ID 构建对应蓝本。
 * @param [IN] id 场景 ID。
 * @return 场景定义；未知 ID 返回酒吧外。
 */
SceneDefinition BuildScene(SceneId id);

} // namespace fc

#endif // __WORLD_SCENEDATA_HPP__
