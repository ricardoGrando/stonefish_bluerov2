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
