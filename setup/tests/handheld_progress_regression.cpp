// Access the manager's tour fixture without constructing ROS maps/controllers.
// Pre-include dependencies before exposing only this class's private fixture.
#include <ros/ros.h>
#include <traj_utils/planning_visualization.h>
#include <actionlib/client/simple_action_client.h>
#include <actionlib/server/simple_action_server.h>
#include <sloam_msgs/ActiveLoopClosureAction.h>
#include <nav_msgs/Odometry.h>
#include <geometry_msgs/Quaternion.h>
#include <utility>
using std::pair;
#include <exploration_msgs/PlanCOPAction.h>
#include <sloam_msgs/EvaluateLoopClosure.h>
#include <std_msgs/UInt64.h>
#include <deque>
#include <unordered_map>
#include <mutex>
#define private public
#include <exploration_manager/ms_exploration_manager.h>
#undef private
#include <exploration_manager/expl_data.h>
#include <cassert>
#include <iostream>
int main() {
  ros::Time::init();
  ms_planner::msExplorationManager manager;
  manager.handheld_feedback_ = true;
  manager.planned_ed_.reset(new ms_planner::ExplorationData);
  manager.handheld_generation_ = 7;
  manager.handheld_initial_ = 3;
  manager.handheld_completed_ = 0;
  manager.active_slam_goal_indices_ = {"ftr0", "clo1", "ftr2"};
  assert(!manager.confirmHandheldObservation({"ftr0",6},false));
  assert(!manager.confirmHandheldObservation({"ftr2",7},false));
  assert(manager.active_slam_goal_indices_.size()==3 && manager.handheld_completed_==0);
  assert(manager.confirmHandheldObservation({"ftr0",7},false));
  assert(manager.handheld_completed_==1 && manager.active_slam_goal_indices_.front()=="clo1");
  assert(!manager.confirmHandheldObservation({"clo1",7},false));
  assert(manager.handheld_completed_==1); // expected SLC is not a measurement
  assert(manager.confirmHandheldObservation({"clo1",7},true));
  assert(manager.handheld_completed_==2);
  assert(manager.skipHandheldGoal({"ftr2",7}));
  assert(manager.handheld_completed_==2 && manager.active_slam_goal_indices_.empty());
  assert(!manager.confirmHandheldObservation({"ftr2",7},false));
  assert(!manager.skipHandheldGoal({"ftr0",7}));
  // Real failure bookkeeping: preserve retries for the same target; skipping
  // cannot count as an observation or carry failures into another target/tour.
  manager.active_slam_goal_indices_ = {"ftr0", "ftr1"};
  manager.plan_fail_cnt_ = 0;
  manager.beginHandheldPlanningAttempt();
  const auto failed_token = manager.handheldGoalToken();
  for (int failures = 1; failures <= 4; ++failures) {
    ++manager.plan_fail_cnt_;
    manager.beginHandheldPlanningAttempt();
    assert(manager.plan_fail_cnt_ == failures);
  }
  assert(manager.skipHandheldGoal(failed_token));
  assert(manager.plan_fail_cnt_ == 0 && manager.handheld_completed_ == 2);
  manager.beginHandheldPlanningAttempt();
  assert(manager.handheldGoalToken().first == "ftr1");
  manager.plan_fail_cnt_ = 2;
  assert(!manager.skipHandheldGoal(failed_token));
  assert(manager.plan_fail_cnt_ == 2); // stale target cannot reset current retries
  ++manager.handheld_generation_;
  manager.beginHandheldPlanningAttempt();
  assert(manager.plan_fail_cnt_ == 0 && manager.handheld_completed_ == 2);
  manager.handheld_feedback_ = false;
  assert(!manager.skipHandheldGoal(manager.handheldGoalToken()));
  manager.handheld_feedback_ = true;
  manager.global_request_id_ = 9;
  manager.global_plan_str_ = {"INIT_PLAN", "PLAN_RECV", "REPLAN"};
  manager.planning_ed_.reset(new ms_planner::ExplorationData);
  manager.planning_ed_->points_.resize(2);
  manager.active_slam_goal_indices_ = {"ftr2"};
  exploration_msgs::PlanCOPResultPtr reply(new exploration_msgs::PlanCOPResult);
  for (const std::vector<int>& invalid : std::vector<std::vector<int>>{{0,0},{0,1,1,0},{0,99,0},{0,-1,0},{}}) {
    reply->sequence = invalid;
    manager.global_plan_state_ = ms_planner::GLOBAL_PLAN_STATE::PLAN_RECV;
    manager.applyGlobalPlan(actionlib::SimpleClientGoalState(actionlib::SimpleClientGoalState::SUCCEEDED),reply,9);
    assert(manager.global_plan_state_ == ms_planner::GLOBAL_PLAN_STATE::INIT_PLAN);
    assert(manager.handheld_completed_ == 2 && manager.active_slam_goal_indices_.size() == 1);
  }
  reply->sequence = {0,1,0};
  manager.applyGlobalPlan(actionlib::SimpleClientGoalState(actionlib::SimpleClientGoalState::SUCCEEDED),reply,8);
  assert(manager.handheld_completed_ == 2 && manager.active_slam_goal_indices_.size() == 1);

  // Global (SLAM) goals and local (VIO) paths must agree after a real correction.
  nav_msgs::OdometryPtr drift(new nav_msgs::Odometry);
  drift->header.stamp = ros::Time::now();
  drift->pose.pose.position.x = 1; drift->pose.pose.position.y = 2; drift->pose.pose.position.z = 3;
  drift->pose.pose.orientation.z = std::sin(M_PI/4);
  drift->pose.pose.orientation.w = std::cos(M_PI/4);
  manager.sloam_to_vio_odom_ = drift;
  assert(manager.handheldDriftReady());
  const auto map_point = manager.handheldDisplayPosition(Eigen::Vector3d(1,4,4));
  // Existing transform helper uses float quaternion components; allow 1 micrometre.
  assert((map_point-Eigen::Vector3d(2,0,1)).norm() < 1e-6);
  drift->pose.pose.orientation.w = 0; drift->pose.pose.orientation.z = 0;
  assert(!manager.handheldDriftReady());

  std::cout << "Handheld manager progress regression passed: stale goals rejected, SLC requires real feedback, skipped goals not counted." << std::endl;
}
