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
