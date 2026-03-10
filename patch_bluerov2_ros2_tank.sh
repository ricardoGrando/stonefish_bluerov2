#!/usr/bin/env bash
set -e

PKG="${1:-$HOME/underwater_ws/src/stonefish_bluerov2}"

if [ ! -d "$PKG" ]; then
  echo "[ERROR] Package path not found: $PKG"
  exit 1
fi

if [ ! -d "$PKG/data/bluerov2" ]; then
  echo "[ERROR] $PKG/data/bluerov2 not found."
  echo "Make sure the original stonefish_bluerov2 package is already there."
  exit 1
fi

mkdir -p "$PKG/launch"
mkdir -p "$PKG/scenarios"
mkdir -p "$PKG/scripts"
mkdir -p "$PKG/data/tank"
mkdir -p "$PKG/stonefish_bluerov2"

cat > "$PKG/stonefish_bluerov2/__init__.py" <<'PY'
PY

cat > "$PKG/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.8)
project(stonefish_bluerov2)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 14)
endif()

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rclpy REQUIRED)

ament_python_install_package(${PROJECT_NAME})

install(PROGRAMS
  scripts/cmd_vel_to_thrusters.py
  DESTINATION lib/${PROJECT_NAME}
)

install(DIRECTORY
  launch
  DESTINATION share/${PROJECT_NAME}/
)

install(DIRECTORY
  scenarios
  DESTINATION share/${PROJECT_NAME}/
)

install(DIRECTORY
  data
  DESTINATION share/${PROJECT_NAME}/
)

ament_package()
EOF

cat > "$PKG/package.xml" <<'EOF'
<?xml version="1.0"?>
<?xml-model href="http://download.ros.org/schema/package_format3.xsd" schematypens="http://www.w3.org/2001/XMLSchema"?>
<package format="3">
  <name>stonefish_bluerov2</name>
  <version>0.1.0</version>
  <description>ROS 2 only BlueROV2 Heavy demo for Stonefish with a 10x10 meter tank scenario.</description>
  <maintainer email="user@example.com">user</maintainer>
  <license>Apache-2.0</license>

  <buildtool_depend>ament_cmake</buildtool_depend>
  <buildtool_depend>ament_cmake_python</buildtool_depend>

  <depend>geometry_msgs</depend>
  <depend>rclcpp</depend>
  <depend>rclpy</depend>
  <depend>std_msgs</depend>

  <exec_depend>launch</exec_depend>
  <exec_depend>launch_ros</exec_depend>

  <test_depend>ament_lint_auto</test_depend>
  <test_depend>ament_lint_common</test_depend>

  <export>
    <build_type>ament_cmake</build_type>
  </export>
</package>
EOF

cat > "$PKG/launch/bluerov2_ros2_tank.launch.py" <<'EOF'
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    vehicle_name = LaunchConfiguration('vehicle_name')
    use_cmd_vel_bridge = LaunchConfiguration('use_cmd_vel_bridge')
    simulation_rate = LaunchConfiguration('simulation_rate')
    rendering_quality = LaunchConfiguration('rendering_quality')
    window_res_x = LaunchConfiguration('window_res_x')
    window_res_y = LaunchConfiguration('window_res_y')

    simulator = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([
            PathJoinSubstitution([
                FindPackageShare('stonefish_ros2'),
                'launch',
                'stonefish_simulator.launch.py'
            ])
        ]),
        launch_arguments={
            'simulation_data': PathJoinSubstitution([FindPackageShare('stonefish_bluerov2'), 'data']),
            'scenario_desc': PathJoinSubstitution([FindPackageShare('stonefish_bluerov2'), 'scenarios', 'bluerov2_tank_10x10.scn']),
            'simulation_rate': simulation_rate,
            'window_res_x': window_res_x,
            'window_res_y': window_res_y,
            'rendering_quality': rendering_quality,
        }.items()
    )

    cmd_vel_bridge = Node(
        package='stonefish_bluerov2',
        executable='cmd_vel_to_thrusters.py',
        name='cmd_vel_to_thrusters',
        output='screen',
        emulate_tty=True,
        parameters=[{
            'vehicle_name': vehicle_name,
        }],
        condition=IfCondition(use_cmd_vel_bridge),
    )

    return LaunchDescription([
        DeclareLaunchArgument('vehicle_name', default_value='bluerov2'),
        DeclareLaunchArgument('use_cmd_vel_bridge', default_value='true'),
        DeclareLaunchArgument('simulation_rate', default_value='200.0'),
        DeclareLaunchArgument('rendering_quality', default_value='high'),
        DeclareLaunchArgument('window_res_x', default_value='1280'),
        DeclareLaunchArgument('window_res_y', default_value='800'),
        simulator,
        cmd_vel_bridge,
    ])
EOF

cat > "$PKG/scripts/cmd_vel_to_thrusters.py" <<'EOF'
#!/usr/bin/env python3
from typing import List

import rclpy
from rclpy.node import Node
from geometry_msgs.msg import Twist
from std_msgs.msg import Float64MultiArray


class CmdVelToThrusters(Node):
    def __init__(self) -> None:
        super().__init__('cmd_vel_to_thrusters')

        self.vehicle_name = self.declare_parameter('vehicle_name', 'bluerov2').value
        self.max_command = float(self.declare_parameter('max_command', 0.65).value)
        self.surge_gain = float(self.declare_parameter('surge_gain', 0.70).value)
        self.sway_gain = float(self.declare_parameter('sway_gain', 0.70).value)
        self.heave_gain = float(self.declare_parameter('heave_gain', 0.70).value)
        self.yaw_gain = float(self.declare_parameter('yaw_gain', 0.45).value)
        self.thruster_scale = list(self.declare_parameter('thruster_scale', [1.0] * 8).value)
        self.thruster_trim = list(self.declare_parameter('thruster_trim', [0.0] * 8).value)

        if len(self.thruster_scale) != 8:
            self.get_logger().warn('thruster_scale must have 8 values. Falling back to all ones.')
            self.thruster_scale = [1.0] * 8
        if len(self.thruster_trim) != 8:
            self.get_logger().warn('thruster_trim must have 8 values. Falling back to all zeros.')
            self.thruster_trim = [0.0] * 8

        cmd_topic = f'/{self.vehicle_name}/cmd_vel'
        thruster_topic = f'/{self.vehicle_name}/thruster_setpoints'

        self.publisher = self.create_publisher(Float64MultiArray, thruster_topic, 10)
        self.subscription = self.create_subscription(Twist, cmd_topic, self.cmd_callback, 10)

        self.get_logger().info(f'Listening on {cmd_topic} and publishing to {thruster_topic}')

    @staticmethod
    def _clip(value: float, limit: float = 1.0) -> float:
        return max(-limit, min(limit, value))

    def _normalize(self, values: List[float]) -> List[float]:
        peak = max(1.0, max(abs(v) for v in values))
        scaled = [v / peak for v in values]
        return [self._clip(v, self.max_command) for v in scaled]

    def cmd_callback(self, msg: Twist) -> None:
        surge = self.surge_gain * msg.linear.x
        sway = self.sway_gain * msg.linear.y
        heave = self.heave_gain * msg.linear.z
        yaw = self.yaw_gain * msg.angular.z

        raw = [
            surge - sway - yaw,
            surge + sway + yaw,
            surge + sway - yaw,
            surge - sway + yaw,
            heave,
            heave,
            heave,
            heave,
        ]

        normalized = self._normalize(raw)
        commanded = [
            self._clip(self.thruster_scale[i] * normalized[i] + self.thruster_trim[i], self.max_command)
            for i in range(8)
        ]

        self.publisher.publish(Float64MultiArray(data=commanded))


def main(args=None) -> None:
    rclpy.init(args=args)
    node = CmdVelToThrusters()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
EOF

chmod +x "$PKG/scripts/cmd_vel_to_thrusters.py"

cat > "$PKG/scenarios/bluerov2_ros2.scn" <<'EOF'
<?xml version="1.0"?>
<scenario>
    <looks>
        <look name="br2" gray="1.0" roughness="0.4" metalness="0.5" texture="bluerov2/br2.png"/>
        <look name="blue" rgb="0.0 0.5 1.0" roughness="0.3"/>
        <look name="black" gray="0.05" roughness="0.2"/>
    </looks>

    <robot name="$(arg vehicle_name)" fixed="false" self_collisions="false">
        <base_link name="base_link" type="compound" physics="submerged">
            <external_part name="HullBottom" type="model" physics="submerged" buoyant="false">
                <physical>
                    <mesh filename="bluerov2/bluerov2_phy.obj" scale="1"/>
                    <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
                    <thickness value="0.005"/>
                </physical>
                <visual>
                    <mesh filename="bluerov2/bluerov2.obj" scale="1"/>
                    <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
                </visual>
                <material name="Fiberglass"/>
                <look name="br2"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
            </external_part>

            <external_part name="HeavyKit" type="model" physics="submerged" buoyant="false">
                <physical>
                    <mesh filename="bluerov2/bluerov2_ring.obj" scale="1"/>
                    <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.03"/>
                    <thickness value="0.005"/>
                </physical>
                <visual>
                    <mesh filename="bluerov2/bluerov2_wings.obj" scale="1"/>
                    <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
                </visual>
                <material name="Fiberglass"/>
                <look name="black"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
            </external_part>

            <internal_part name="BackLeft" type="box" physics="submerged" buoyant="true">
                <dimensions xyz="0.2 0.15 0.091"/>
                <origin xyz="0.0 0.0 0.0" rpy="0.0 0.0 0.0"/>
                <material name="Neutral"/>
                <look name="None"/>
                <mass value="0.025"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="-0.1 -0.1 0.0"/>
            </internal_part>

            <internal_part name="BackRight" type="box" physics="submerged" buoyant="true">
                <dimensions xyz="0.2 0.15 0.091"/>
                <origin xyz="0.0 0.0 0.0" rpy="0.0 0.0 0.0"/>
                <material name="Neutral"/>
                <look name="None"/>
                <mass value="0.025"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="-0.1 0.1 0.0"/>
            </internal_part>

            <internal_part name="FrontLeft" type="box" physics="submerged" buoyant="true">
                <dimensions xyz="0.2 0.15 0.091"/>
                <origin xyz="0.0 0.0 0.0" rpy="0.0 0.0 0.0"/>
                <material name="Neutral"/>
                <look name="None"/>
                <mass value="0.025"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="0.09 -0.1 0.0"/>
            </internal_part>

            <internal_part name="FrontRight" type="box" physics="submerged" buoyant="true">
                <dimensions xyz="0.2 0.15 0.091"/>
                <origin xyz="0.0 0.0 0.0" rpy="0.0 0.0 0.0"/>
                <material name="Neutral"/>
                <look name="None"/>
                <mass value="0.025"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="0.09 0.1 0.0"/>
            </internal_part>

            <internal_part name="WeightCenter" type="sphere" physics="submerged" buoyant="false">
                <dimensions radius="0.01"/>
                <origin xyz="0.0 0.0 0.0" rpy="0.0 0.0 0.0"/>
                <material name="Steel"/>
                <look name="black"/>
                <mass value="2.0"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.1"/>
            </internal_part>

            <internal_part name="WeightLeft" type="sphere" physics="submerged" buoyant="false">
                <dimensions radius="0.01"/>
                <origin xyz="0.0 0.0 0.0" rpy="0.0 0.0 0.0"/>
                <material name="Steel"/>
                <look name="black"/>
                <mass value="1.0"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="0.0 -0.075 0.1"/>
            </internal_part>

            <internal_part name="WeightRight" type="sphere" physics="submerged" buoyant="false">
                <dimensions radius="0.01"/>
                <origin xyz="0.0 0.0 0.0" rpy="0.0 0.0 0.0"/>
                <material name="Steel"/>
                <look name="black"/>
                <mass value="1.0"/>
                <compound_transform rpy="0.0 0.0 0.0" xyz="0.0 0.075 0.1"/>
            </internal_part>
        </base_link>

        <actuator name="FrontRight" type="thruster">
            <link name="base_link"/>
            <origin xyz="0.1355 0.1 0.0725" rpy="0 0 -0.7853981634"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="true"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="true">
                <mesh filename="bluerov2/ccw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <actuator name="FrontLeft" type="thruster">
            <link name="base_link"/>
            <origin xyz="0.1355 -0.1 0.0725" rpy="0 0 0.7853981634"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="true"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="true">
                <mesh filename="bluerov2/ccw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <actuator name="BackRight" type="thruster">
            <link name="base_link"/>
            <origin xyz="-0.1475 0.1 0.0725" rpy="0 0 -2.3561944902"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="false"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="false">
                <mesh filename="bluerov2/cw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <actuator name="BackLeft" type="thruster">
            <link name="base_link"/>
            <origin xyz="-0.1475 -0.1 0.0725" rpy="0 0 2.3561944902"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="false"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="false">
                <mesh filename="bluerov2/cw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <actuator name="DiveFrontRight" type="thruster">
            <link name="base_link"/>
            <origin xyz="0.12 0.218 0.0" rpy="0 -1.5707963268 0"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="false"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="true">
                <mesh filename="bluerov2/cw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <actuator name="DiveFrontLeft" type="thruster">
            <link name="base_link"/>
            <origin xyz="0.12 -0.218 0.0" rpy="0 -1.5707963268 0"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="true"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="false">
                <mesh filename="bluerov2/ccw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <actuator name="DiveBackRight" type="thruster">
            <link name="base_link"/>
            <origin xyz="-0.12 0.218 0.0" rpy="0 -1.5707963268 0"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="true"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="false">
                <mesh filename="bluerov2/ccw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <actuator name="DiveBackLeft" type="thruster">
            <link name="base_link"/>
            <origin xyz="-0.12 -0.218 0.0" rpy="0 -1.5707963268 0"/>
            <specs thrust_coeff="0.167" torque_coeff="0.016" max_rpm="3600.0" inverted="false"/>
            <watchdog timeout="1.0"/>
            <propeller diameter="0.076" right="true">
                <mesh filename="bluerov2/cw.obj" scale="1.0"/>
                <material name="Neutral"/>
                <look name="blue"/>
            </propeller>
        </actuator>

        <sensor name="odom" type="odometry" rate="100.0">
            <link name="base_link"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
            <ros_publisher topic="/$(arg vehicle_name)/odom"/>
        </sensor>

        <sensor name="imu" type="imu" rate="50.0">
            <link name="base_link"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
            <noise angle="0.000001745" angular_velocity="0.00001745" linear_acceleration="0.00005"/>
            <ros_publisher topic="/$(arg vehicle_name)/imu"/>
        </sensor>

        <sensor name="pressure" type="pressure" rate="10.0">
            <link name="base_link"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
            <noise pressure="5.0"/>
            <ros_publisher topic="/$(arg vehicle_name)/pressure"/>
        </sensor>

        <sensor name="dvl" type="dvl" rate="10.0">
            <link name="base_link"/>
            <origin rpy="3.1416 0.0 0.0" xyz="0.0 0.0 0.0"/>
            <specs beam_angle="30.0"/>
            <range velocity="9.0 9.0 9.0" altitude_min="0.2" altitude_max="30.0"/>
            <noise velocity="0.0015" altitude="0.001"/>
            <ros_publisher topic="/$(arg vehicle_name)/dvl" altitude_topic="/$(arg vehicle_name)/altitude"/>
        </sensor>

        <world_transform xyz="$(arg position)" rpy="$(arg orientation)"/>
        <ros_subscriber thrusters="/$(arg vehicle_name)/thruster_setpoints"/>
        <ros_publisher thrusters="/$(arg vehicle_name)/thruster_state"/>
    </robot>
</scenario>
EOF

cat > "$PKG/scenarios/bluerov2_tank_10x10.scn" <<'EOF'
<?xml version="1.0"?>
<scenario>
    <environment>
        <ned latitude="56.136459" longitude="-2.706819"/>
        <ocean>
            <water density="1031.0" jerlov="0.15"/>
            <waves height="0.0"/>
            <particles enabled="true"/>
            <current type="uniform">
                <velocity xyz="0.0 0.0 0.0"/>
            </current>
            <current type="jet">
                <center xyz="0.0 0.0 0.0"/>
                <outlet radius="100.0"/>
                <velocity xyz="0.0 0.0 0.0"/>
            </current>
        </ocean>
        <atmosphere>
            <sun azimuth="45.0" elevation="80.0"/>
        </atmosphere>
    </environment>

    <materials>
        <material name="Neutral" density="1000.0" restitution="0.1"/>
        <material name="Rock" density="3000.0" restitution="0.8"/>
        <material name="Fiberglass" density="1500.0" restitution="0.3"/>
        <material name="Aluminium" density="2710.0" restitution="0.5"/>
        <material name="Steel" density="7810.0" restitution="0.8"/>
        <friction_table>
            <friction material1="Neutral" material2="Neutral" static="0.5" dynamic="0.2"/>
            <friction material1="Neutral" material2="Rock" static="0.2" dynamic="0.1"/>
            <friction material1="Neutral" material2="Fiberglass" static="0.5" dynamic="0.2"/>
            <friction material1="Neutral" material2="Aluminium" static="0.1" dynamic="0.02"/>
            <friction material1="Neutral" material2="Steel" static="0.2" dynamic="0.1"/>
            <friction material1="Rock" material2="Rock" static="0.9" dynamic="0.7"/>
            <friction material1="Rock" material2="Fiberglass" static="0.6" dynamic="0.4"/>
            <friction material1="Rock" material2="Aluminium" static="0.6" dynamic="0.3"/>
            <friction material1="Steel" material2="Steel" static="0.5" dynamic="0.3"/>
            <friction material1="Fiberglass" material2="Fiberglass" static="0.5" dynamic="0.2"/>
            <friction material1="Fiberglass" material2="Aluminium" static="0.5" dynamic="0.2"/>
            <friction material1="Aluminium" material2="Aluminium" static="0.8" dynamic="0.5"/>
        </friction_table>
    </materials>

    <looks>
        <look name="black" gray="0.05" roughness="0.2"/>
        <look name="tank_wall" rgb="0.88 0.9 0.92" roughness="0.9"/>
        <look name="tank_floor" rgb="0.72 0.75 0.78" roughness="0.95"/>
    </looks>

    <static name="TankFloor" type="model">
        <physical>
            <mesh filename="tank/floor_10x10.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </physical>
        <visual>
            <mesh filename="tank/floor_10x10.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </visual>
        <material name="Rock"/>
        <look name="tank_floor"/>
        <world_transform rpy="0.0 0.0 0.0" xyz="0.0 0.0 4.05"/>
    </static>

    <static name="TankWallNorth" type="model">
        <physical>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </physical>
        <visual>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </visual>
        <material name="Rock"/>
        <look name="tank_wall"/>
        <world_transform rpy="0.0 0.0 0.0" xyz="0.0 5.0 0.0"/>
    </static>

    <static name="TankWallSouth" type="model">
        <physical>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </physical>
        <visual>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </visual>
        <material name="Rock"/>
        <look name="tank_wall"/>
        <world_transform rpy="0.0 0.0 0.0" xyz="0.0 -5.0 0.0"/>
    </static>

    <static name="TankWallEast" type="model">
        <physical>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </physical>
        <visual>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </visual>
        <material name="Rock"/>
        <look name="tank_wall"/>
        <world_transform rpy="0.0 0.0 1.5707963268" xyz="5.0 0.0 0.0"/>
    </static>

    <static name="TankWallWest" type="model">
        <physical>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </physical>
        <visual>
            <mesh filename="tank/wall_10x4.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </visual>
        <material name="Rock"/>
        <look name="tank_wall"/>
        <world_transform rpy="0.0 0.0 1.5707963268" xyz="-5.0 0.0 0.0"/>
    </static>

    <light name="TankLight">
        <specs radius="0.2" illuminance="2500.0"/>
        <color rgb="1.0 1.0 1.0"/>
        <world_transform xyz="0.0 0.0 0.3" rpy="0.0 0.0 0.0"/>
    </light>

    <include file="$(find stonefish_bluerov2)/scenarios/bluerov2_ros2.scn">
        <arg name="vehicle_name" value="bluerov2"/>
        <arg name="position" value="0.0 0.0 1.5"/>
        <arg name="orientation" value="0.0 0.0 0.0"/>
    </include>
</scenario>
EOF

cat > "$PKG/data/tank/floor_10x10.obj" <<'EOF'
o floor_10x10
v -5.0 -5.0 -0.05
v  5.0 -5.0 -0.05
v  5.0  5.0 -0.05
v -5.0  5.0 -0.05
v -5.0 -5.0  0.05
v  5.0 -5.0  0.05
v  5.0  5.0  0.05
v -5.0  5.0  0.05
f 1 2 3 4
f 5 8 7 6
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 4 8 5 1
EOF

cat > "$PKG/data/tank/wall_10x4.obj" <<'EOF'
o wall_10x4
v -5.0 -0.05 0.0
v  5.0 -0.05 0.0
v  5.0  0.05 0.0
v -5.0  0.05 0.0
v -5.0 -0.05 4.0
v  5.0 -0.05 4.0
v  5.0  0.05 4.0
v -5.0  0.05 4.0
f 1 2 3 4
f 5 8 7 6
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 4 8 5 1
EOF

echo
echo "[OK] Package patched at: $PKG"
echo
echo "Now rebuild with:"
echo "  cd ~/underwater_ws"
echo "  colcon build --packages-select stonefish_ros2 stonefish_bluerov2"
echo "  source install/setup.bash"
echo
echo "Launch with:"
echo "  ros2 launch stonefish_bluerov2 bluerov2_ros2_tank.launch.py"
