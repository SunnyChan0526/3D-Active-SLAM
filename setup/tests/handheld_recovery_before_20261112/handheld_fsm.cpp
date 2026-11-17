#include <plan_manage/planner_manager.h>
#include <exploration_manager/ms_exploration_fsm.h>
#include <exploration_manager/ms_exploration_manager.h>
#include <exploration_manager/expl_data.h>
#include <exploration_manager/handheld_policy.h>
#include <active_perception/frontier_finder.h>
#include <plan_env/sdf_map.h>
#include <plan_env/edt_environment.h>
#include <cmath>

namespace ms_planner {
void msExplorationFSM::handheldCancelClosure() {
  ++handheld_closure_request_;
  active_closure_client_ptr_->cancelAllGoals();
  handheld_closure_result_.store(0);
}

void msExplorationFSM::handheldStatus(const std::string& status) {
  if (status == handheld_last_status_) return;
  handheld_last_status_ = status;
  std_msgs::String msg; msg.data = status;
  handheld_status_pub_.publish(msg);
  ROS_INFO_STREAM("[Handheld Auto] " << status);
}

bool msExplorationFSM::handheldEnable(std_srvs::SetBool::Request& request,
                                     std_srvs::SetBool::Response& response) {
  response.success = handheld_auto_ && planning_only_;
  if (!response.success) { response.message = "requires handheld_auto and planning_only"; return true; }
  handheld_armed_ = request.data;
  if (!handheld_armed_) {
    handheldCancelClosure();
    handheld_closure_wait_ = false;
    handheld_has_goal_ = false;
    handheld_waiting_ = false;
    handheldVisualize(false);
  }
  response.message = handheld_armed_ ? "automatic planning enabled" : "automatic planning paused";
  handheldStatus(handheld_armed_ ? "已啟用：等待新鮮定位與地圖，自動開始規劃。" : "自動規劃已暫停。");
  return true;
}

void msExplorationFSM::handheldVisualize(bool local_valid) {
  visualization_msgs::Marker path;
  path.header.frame_id = "world";
  path.header.stamp = ros::Time::now();
  path.ns = "handheld_local_path"; path.id = 0;
  path.type = visualization_msgs::Marker::LINE_STRIP;
  path.action = local_valid ? visualization_msgs::Marker::ADD : visualization_msgs::Marker::DELETE;
  path.pose.orientation.w = 1;
  path.scale.x = .08;
  path.color.g = .8; path.color.b = 1; path.color.a = 1;
  if (local_valid) {
    auto& traj = planner_manager_->local_data_.traj_;
    const double duration = traj.getTotalDuration();
    for (int i = 0; i <= 100; ++i) {
      const Vector3d p = expl_manager_->handheldDisplayPosition(traj.getPos(duration * i / 100.0));
      geometry_msgs::Point point; point.x = p.x(); point.y = p.y(); point.z = p.z();
      path.points.push_back(point);
    }
  }
  handheld_path_pub_.publish(path);
  visualization_msgs::Marker goal = path;
  goal.ns = "handheld_goal"; goal.type = visualization_msgs::Marker::ARROW;
  goal.action = handheld_has_goal_ ? visualization_msgs::Marker::ADD : visualization_msgs::Marker::DELETE;
  goal.points.clear(); goal.scale.x = .8; goal.scale.y = .15; goal.scale.z = .15;
  goal.pose.position.x = handheld_goal_.x(); goal.pose.position.y = handheld_goal_.y(); goal.pose.position.z = handheld_goal_.z();
  goal.pose.orientation.z = std::sin(handheld_goal_yaw_ / 2);
  goal.pose.orientation.w = std::cos(handheld_goal_yaw_ / 2);
  goal.color.r = 1; goal.color.g = .5; goal.color.b = 0;
  handheld_goal_pub_.publish(goal);
}

void msExplorationFSM::handheldStep() {
  if (!handheld_armed_) return;
  const ros::Time now = ros::Time::now();
  if (expl_manager_->ep_->closure_just_triggered_ &&
      (now - closure_trigger_time_).toSec() >= 60.0)
    expl_manager_->ep_->closure_just_triggered_ = false;
  auto pause = [this]() {
    if (handheld_closure_wait_) handheldCancelClosure();
    handheld_closure_wait_ = false;
    handheld_has_goal_ = false;
    handheld_observation_since_ = ros::Time(0);
    handheldVisualize(false);
  };
  const double vio_age = (now - odom_time_).toSec();
  const double slam_age = (now - slam_odom_time_).toSec();
  if (!fd_->have_odom_ || vio_age < 0 || vio_age > .5 || slam_age < 0 || slam_age > 1.0 ||
      !fd_->vio_odom_pos_.allFinite() || !fd_->slam_odom_pos_.allFinite() ||
      !fd_->vio_odom_vel_.allFinite() || !std::isfinite(fd_->vio_odom_yaw_) ||
      fd_->vio_odom_vel_.norm() > 2.0) {
    handheldStatus("定位不新鮮或移動異常，暫停規劃；不會假定已走完路線。");
    pause();
    return;
  }
  if (!expl_manager_->handheldDriftReady()) {
    handheldStatus("等待 SLOAM 與 VINS 的真實座標補償資料，暫不規劃。");
    pause();
    return;
  }
  auto map = planner_manager_->edt_environment_->occ_map_;
  if (!map->isInBox(fd_->slam_odom_pos_)) {
    handheldStatus("目前位置超出地圖範圍，暫停規劃；請回到有效範圍。");
    pause();
    return;
  }
  if (map->getInflateOccupancy(fd_->slam_odom_pos_) == 1) {
    handheldStatus("目前位置在障礙物安全範圍內，請離開牆壁或桌椅再繼續。");
    pause();
    return;
  }
  if (handheld_has_goal_ && !expl_manager_->handheldGoalCurrent(handheld_goal_token_)) {
    if (handheld_closure_wait_) handheldCancelClosure();
    handheld_closure_wait_ = false;
    handheld_has_goal_ = false;
  }
  if (handheld_has_goal_ && handheld_closure_wait_ &&
      handheldClosureResult(handheld_closure_result_.load(), handheld_closure_request_) == 1) {
    // A real SLC may correct the map frame. Do not mistake that correction
    // for the person leaving the old goal before processing its successful result.
    expl_manager_->confirmHandheldObservation(handheld_goal_token_, true);
    handheld_has_goal_ = false;
    handheld_closure_wait_ = false;
    handheldStatus("真實語意迴環量測成功，重新評估探索路線。");
  }
  if (handheld_has_goal_) {
    const double distance = (fd_->slam_odom_pos_ - handheld_goal_).norm();
    const double yaw_error = range(fd_->slam_odom_yaw_ - handheld_goal_yaw_);
    const bool closure = handheld_goal_token_.first.find("clo") == 0;
    if (closure && distance <= .5) {
      if (!handheld_closure_wait_) {
        // Only request semantic measurement processing, never a motion command.
        std::lock_guard<std::mutex> lock(expl_manager_->mutex_);
        expl_manager_->planned_ed_->closure_planned_ = true;
        expl_manager_->ep_->closure_just_triggered_ = false;
        handheld_closure_result_.store(0);
        triggerClosureService();
        handheld_closure_wait_ = true;
        handheld_closure_start_ = now;
        closure_trigger_time_ = now;
      }
      const int result = handheldClosureResult(handheld_closure_result_.load(), handheld_closure_request_);
      if (result == 1) {
        expl_manager_->confirmHandheldObservation(handheld_goal_token_, true);
        handheld_has_goal_ = false; handheld_closure_wait_ = false;
        handheldStatus("真實語意迴環量測成功，重新評估探索路線。");
      } else if (result < 0 || (now - handheld_closure_start_).toSec() > 45) {
        handheldCancelClosure();
        expl_manager_->skipHandheldGoal(handheld_goal_token_);
        handheld_has_goal_ = false; handheld_closure_wait_ = false;
        handheldStatus("此次語意迴環未成功，不計為完成；繼續評估其他目標。");
      } else {
        handheldStatus("已到語意迴環位置：請保持位置，慢慢原地轉一圈掃描；等候真實迴環結果。");
        return;
      }
    } else if (handheld_closure_wait_) {
      handheldCancelClosure();
      handheld_closure_wait_ = false;
      handheldStatus("已離開語意迴環位置，停止本次量測等待。");
    } else if (!closure && handheldReached(distance, yaw_error)) {
      if (handheld_observation_since_.isZero()) handheld_observation_since_ = now;
      if ((now - handheld_observation_since_).toSec() < 1.0) return;
      expl_manager_->confirmHandheldObservation(handheld_goal_token_, false);
      handheld_has_goal_ = false;
      handheld_observation_since_ = ros::Time(0);
      handheldStatus("已依實際位置與朝向到達觀察點，更新路線。");
    } else {
      handheld_observation_since_ = ros::Time(0);
    }
  }
  if ((now - handheld_last_plan_).toSec() < (handheld_waiting_ ? .2 : 1.0)) return;
  const bool moved = (fd_->vio_odom_pos_ - handheld_plan_pos_).norm() >= .5 ||
                     std::abs(range(fd_->vio_odom_yaw_ - handheld_plan_yaw_)) >= .35;
  const bool path_blocked = handheld_has_goal_ && !planner_manager_->local_data_.traj_.is_empty() &&
      planner_manager_->checkTrajCollision(planner_manager_->local_data_.traj_) >= 0;
  if (path_blocked) handheldVisualize(false);
  if (!handheld_waiting_ && handheld_has_goal_ && !moved && !path_blocked &&
      !expl_manager_->handheldNeedsGlobalRefresh()) return;
  if (handheld_waiting_ && (now - handheld_wait_start_).toSec() > 30) {
    expl_manager_->resetHandheldGlobalRequest();
    handheld_waiting_ = false;
    handheldStatus("COP 等待逾時，保留真實定位並稍後重試。");
    handheld_last_plan_ = now;
    return;
  }
  // Always start from measured odometry. Never enter EXEC_TRAJ, INIT_ROTATE,
  // or CLOSURE_PANO, whose original implementations send tracker commands.
  fd_->static_state_ = true;
  updateStartState(0.0);
  handheld_last_plan_ = now;
  state_ = PLAN_BEHAVIOR;
  const int result = callExplorationPlanner();
  ROS_INFO_STREAM("[Handheld Plan Result] " << result);
  if (result == EXPL_RESULT::WAIT_PLAN || result == EXPL_RESULT::RANDOM_ROTATE) {
    if (!handheld_waiting_) handheld_wait_start_ = now;
    handheld_waiting_ = true;
    handheldStatus("正在非同步更新 COP 全域路線。");
    return;
  }
  handheld_waiting_ = false;
  if (result == EXPL_RESULT::SUCCEED || result == EXPL_RESULT::TARGET_ROTATE ||
      result == EXPL_RESULT::SUCCEED_AND_STAY) {
    handheld_has_goal_ = true;
    handheld_observation_since_ = ros::Time(0);
    handheld_goal_ = replan_next_pos_; // SLAM/map coordinates, including SLC goals
    handheld_goal_yaw_ = replan_next_yaw_;
    handheld_goal_token_ = expl_manager_->handheldGoalToken();
    handheld_plan_pos_ = fd_->vio_odom_pos_;
    handheld_plan_yaw_ = fd_->vio_odom_yaw_;
    {
      std::lock_guard<std::mutex> lock(expl_manager_->mutex_);
      visualize();
    }
    handheldVisualize(result == EXPL_RESULT::SUCCEED);
    state_ = FINISH; // observation wait; automatic mode continues in handheldStep
    if (result == EXPL_RESULT::TARGET_ROTATE)
      handheldStatus("已接近目標：請在原地慢慢轉向橘色箭頭方向；系統會確認實際朝向。");
    else if (result == EXPL_RESULT::SUCCEED_AND_STAY)
      handheldStatus("已到目標附近，請保持位置與朝向一秒，確認真實觀察後繼續。");
    else handheldStatus("路線已更新：青色線為本段可行軌跡，橘色箭頭為觀察目標；依實際移動持續更新。");
  } else {
    if (result == EXPL_RESULT::FAIL && expl_manager_->plan_fail_cnt_ > 3) {
      expl_manager_->skipHandheldGoal(expl_manager_->handheldGoalToken());
      expl_manager_->plan_fail_cnt_ = 0;
    }
    handheld_has_goal_ = false;
    state_ = FINISH;
    handheldVisualize(false);
    handheldStatus(result == EXPL_RESULT::NO_FRONTIER ?
        "目前沒有可用探索目標；繼續觀察環境，地圖更新後自動重試。" :
        "此次局部規劃未通過，不顯示為可行路線；地圖或位置更新後自動重試。");
  }
}
}
