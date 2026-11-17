#ifndef _EXPLORATION_MANAGER_H_
#define _EXPLORATION_MANAGER_H_

#include <ros/ros.h>
#include <Eigen/Eigen>
#include <visualization_msgs/Marker.h>
#include <visualization_msgs/MarkerArray.h>
#include <traj_utils/planning_visualization.h>
#include <memory>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <string>
#include "exploration_msgs/PlanCOPAction.h"
#include "sloam_msgs/EvaluateLoopClosure.h"
#include "sloam_msgs/ActiveLoopClosureAction.h"
#include <actionlib/client/simple_action_client.h>
#include <actionlib/server/simple_action_server.h>
#include <std_msgs/UInt64.h>
#include <mutex>
#include <deque>

#include <nav_msgs/Odometry.h>
#include <geometry_msgs/Quaternion.h>


using Eigen::Vector3d;
using std::shared_ptr;
using std::unique_ptr;
using std::vector;

namespace ms_planner {
class EDTEnvironment;
class SDFMap;
class msPlannerManager;
class FrontierFinder;
struct ExplorationParam;
struct ExplorationData;
struct FSMData;

enum EXPL_RESULT { NO_FRONTIER, FAIL, WAIT_PLAN, SUCCEED, SUCCEED_AND_STAY, TARGET_ROTATE, RANDOM_ROTATE, CLOSURE_SET, CLOSURE_FAIL};
enum GLOBAL_PLAN_STATE {INIT_PLAN, PLAN_RECV, REPLAN};

class msExplorationManager {
public:
  msExplorationManager();
  ~msExplorationManager();

  void initialize(ros::NodeHandle& nh);


  int planExploreMotionBC(const Vector3d& pos, const Vector3d& vel, const Vector3d& acc, 
                          const Vector3d& yaw);

  int planExploreMotionCOP(
      const Vector3d &pos, // in VIO frame
       const Vector3d &pos_slam, // in slam frame
       const Vector3d &vel, // in VIO frame
       const Vector3d &acc, // in VIO frame
       const Vector3d &yaw, // in VIO frame
       const Vector3d &yaw_slam); // in slam frame

  int computeFrontierUtilities(const Vector3d& cur_pos, const Vector3d& vel, const Vector3d& cur_yaw, 
                                const vector<Eigen::Vector3d>& points, const vector<double>& yaws,
                                const vector<int>& info_gains, vector<double>& costs, vector<double>& utilities);
  int planBC(const Vector3d &next_pos_input, // In slam frame
                                   const double &next_yaw_input, // In slam frame
                                   const Vector3d &pos, // In VIO frame
                                   const Vector3d &pos_slam, // in slam frame
                                   const Vector3d &vel, // in VIO frame
                                   const Vector3d &acc, // in VIO frame
                                   const Vector3d &yaw, // in VIO frame, 
                                   const Vector3d &yaw_slam // in slam frame, 
                                   );

  void globalPlanDoneCB(const actionlib::SimpleClientGoalState &state,
                        const exploration_msgs::PlanCOPResultConstPtr &result, size_t request_id);
  void planActiveLoopClosurePath(const Vector3d& curr_pos, const std::vector<int>& index_sequence, const double& budget, 
                                const std::vector<double>& cost_mat, const std::vector<double>& corr_mat, const int& dim, 
                                const size_t& curr_pose_idx, const std::vector<int>& key_pose_ids, 
                                const std::unordered_map<int, Eigen::Vector3d>& key_pose_pos,
                                const std::unordered_map<int, Eigen::Vector3d>& key_pose_centroids,
                                std::vector<std::string>& refined_sequence);

  // Exploration global planning state transition
  void transitGlobalPlanState(GLOBAL_PLAN_STATE new_state, std::string pos_call);

  void copyEdToPlanning();
  void copyPlanningEdToPlanned();
  GLOBAL_PLAN_STATE global_plan_state_;
  vector<std::string> global_plan_str_;

  shared_ptr<ExplorationData> ed_, planning_ed_, planned_ed_;
  shared_ptr<ExplorationParam> ep_;
  shared_ptr<FSMData> fd_;
  shared_ptr<msPlannerManager> planner_manager_;
  shared_ptr<FrontierFinder> frontier_finder_;
  visualization_msgs::Marker mk;
  void getReplanGoal(Vector3d &replan_next_pos, double &replan_next_yaw)
  {
    replan_next_pos = replan_next_pos_;
    replan_next_yaw  = replan_next_yaw_;
  }

  void setVis(shared_ptr<PlanningVisualization> &vis);
  std::vector<Vector3d> goal_seq_pos;
  int plan_fail_cnt_ = 0;
  bool handheld_feedback_ = false;
  // Handheld Testing Mode, Option A (default off): reachable camera z range.
  bool handheld_height_limit_ = false;
  double handheld_z_min_ = 0.0, handheld_z_max_ = 0.0;
  bool handheldNeedsGlobalRefresh();
  bool handheldUnplannedClosure();
  int planHandheldClosureOnly(const Vector3d& graph_pos, const Vector3d& pos, const Vector3d& pos_slam,
                              const Vector3d& vel, const Vector3d& acc, const Vector3d& yaw,
                              const Vector3d& yaw_slam);
  bool confirmHandheldObservation(const std::pair<std::string, size_t>& token, bool closure_observed);
  bool skipHandheldGoal(const std::pair<std::string, size_t>& token);
  std::pair<std::string, size_t> handheldGoalToken();
  bool handheldGoalCurrent(const std::pair<std::string, size_t>& token);
  void resetHandheldGlobalRequest();
  Vector3d handheldDisplayPosition(const Vector3d& vio_position);
  bool handheldDriftReady() const;
  
  std::mutex mutex_;
  // Each id is a cluster of candidate closure
  std::vector<int> loop_closure_ids_, planned_closure_ids_;
  // Key pose is the xyz of the keypose in the factor graph
  std::unordered_map<int, Eigen::Vector3d> loop_closure_id_to_pose_,
      planned_closure_id_to_pose_;
  // Centroid is the xyz of the cluster centroid
  std::unordered_map<int, Eigen::Vector3d> loop_closure_id_to_cluster_centroid_,
      planned_closure_id_to_cluster_centroid_;
  // Landmarks are the xyz of all the landmarks in the cluster
  std::unordered_map<int, std::vector<Eigen::Vector3d>>
      loop_closure_id_to_landmarks_, planeed_closure_id_to_landmarks_;



private:
  ros::Timer handheld_cop_result_timer_;
  struct PendingCopResult {
    actionlib::SimpleClientGoalState state;
    exploration_msgs::PlanCOPResultConstPtr result;
    size_t request_id;
  };
  std::mutex handheld_result_mutex_;
  std::deque<PendingCopResult> handheld_results_;
  void applyGlobalPlan(const actionlib::SimpleClientGoalState& state,
                       const exploration_msgs::PlanCOPResultConstPtr& result, size_t request_id);

  typedef actionlib::SimpleActionClient<exploration_msgs::PlanCOPAction> GlobalPlanClientType;

  std::unique_ptr<GlobalPlanClientType> global_plan_client_ptr_;

  shared_ptr<EDTEnvironment> edt_environment_;
  shared_ptr<SDFMap> global_map_;

  void compensateDrift(const Vector3d& position,
      const double& yaw, Vector3d& position_out, double& yaw_out);

  // A action client wrapper to send global tour planning request to COP server 
  void findGlobalTour(const Vector3d& cur_pos, const Vector3d& cur_vel, const Vector3d cur_yaw, const vector<int>& info_gains);

  // Refine local tour for next few frontiers, using more diverse viewpoints
  void refineLocalTour(const Vector3d& cur_pos, const Vector3d& cur_vel, const Vector3d& cur_yaw,
                       const vector<vector<Vector3d>>& n_points, const vector<vector<double>>& n_yaws,
                       vector<Vector3d>& refined_pts, vector<double>& refined_yaws);

  void shortenPath(vector<Vector3d>& path);
  void latestKeyPoseCallback_(const std_msgs::UInt64ConstPtr &msg);
  void loopClosureSubmapCallback_(const visualization_msgs::MarkerArrayConstPtr &msg);
  void sloamToVioCallback_(const nav_msgs::OdometryConstPtr &msg);

  Eigen::Matrix4d odometryToTransformationMatrix(
      const nav_msgs::Odometry &odometry_msg);
  Eigen::Matrix3d quaternionToRotationMatrix(const geometry_msgs::Quaternion &q);

  nav_msgs::OdometryConstPtr sloam_to_vio_odom_ = nullptr;
  ros::Publisher next_goal_pub_, next_goal_compensated_pub_;
  Vector3d replan_next_pos_;
  double replan_next_yaw_;

  // The exploration sequence and refined sequence
  std::vector<int> goal_indices_;
  std::vector<std::string>
      active_slam_goal_indices_;  // ftr0 ftr2 for frontiers... or clo0 clo1
                                  // for closure
  int init_tour_len_ = 0;
  size_t handheld_completed_ = 0, handheld_initial_ = 0;
  size_t handheld_generation_ = 0;
  bool handheld_unplanned_closure_logged_ = false;
  std::unordered_set<int> handheld_seen_closure_ids_;      // offered to COP at least once
  std::unordered_set<int> handheld_attempted_closure_ids_; // given as closure-only goal
  ros::Time handheld_last_tour_time_;
  size_t global_request_id_ = 0;
  std::pair<std::string, size_t> handheld_last_planned_token_;
  void beginHandheldPlanningAttempt();

  bool is_planning_ = false;

  double radius_far_ = 7.0;
  double radius_close_ = 2.0;
  double radius_noplan_ = 0.5;
  double v_fov_;
  double server_wait_timeout_;
  ros::Subscriber latest_key_pose_sub_;
  ros::Subscriber loop_closure_submap_sub_;
  ros::Subscriber sloam_to_vio_odom_sub_;
  // ros::Subscriber  subscribe high frequency odom
  size_t latest_key_pose_idx_;
  ros::ServiceClient estimate_closure_ig_client_;

 public:
  typedef shared_ptr<msExplorationManager> Ptr;
};

}  // namespace ms_planner

#endif


