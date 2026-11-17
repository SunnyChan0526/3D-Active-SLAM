// Offline multi-segment preview. This executable has no tracker/flight command path.
#include <plan_manage/planner_manager.h>
#include <active_perception/graph_node.h>
#include <plan_env/raycast.h>
#include <exploration_msgs/PlanCOPAction.h>
#include <actionlib/client/simple_action_client.h>
#include <std_srvs/Trigger.h>
#include <std_msgs/String.h>
#include <visualization_msgs/MarkerArray.h>
#include <pcl_conversions/pcl_conversions.h>
#include <nav_msgs/Odometry.h>
#include <set>
#include <sstream>
#include <cmath>

namespace ms_planner {
using V3 = Eigen::Vector3d;
using Marker = visualization_msgs::Marker;
class PlanningPreview {
  using COP = actionlib::SimpleActionClient<exploration_msgs::PlanCOPAction>;
  ros::NodeHandle nh_;
  msPlannerManager planner_;
  PlanningVisualization::Ptr vis_;
  std::shared_ptr<FrontierFinder> frontier_;
  std::unique_ptr<COP> cop_;
  ros::Subscriber vio_sub_, slam_sub_;
  ros::Publisher markers_pub_, map_pub_, status_pub_;
  ros::ServiceServer start_srv_, pause_srv_, resume_srv_, stop_srv_;
  ros::WallTimer timer_;
  nav_msgs::Odometry vio_, slam_;
  bool have_vio_ = false, have_slam_ = false, paused_ = false;
  enum State { IDLE, WAIT_TOUR, PLAN, PLAY, FINISHED, FAILED } state_ = IDLE;
  Eigen::Isometry3d slam_from_vio_ = Eigen::Isometry3d::Identity();
  std::vector<V3> candidates_, goals_, history_, segment_;
  std::vector<double> candidate_yaws_, goal_yaws_;
  std::vector<std::vector<V3>> frontiers_;
  Eigen::Matrix3d virtual_state_ = Eigen::Matrix3d::Zero();
  V3 virtual_yaw_ = V3::Zero(), segment_start_ = V3::Zero();
  size_t goal_index_ = 0;
  int segments_ = 0, stalls_ = 0, max_segments_ = 100, max_goals_ = 0;
  double elapsed_ = 0, position_tolerance_ = 0.15, yaw_tolerance_ = 0.1, playback_speed_ = 1;
  ros::WallTime last_tick_, request_time_;
  std::string status_ = "IDLE: snapshot preview, no UAV execution";

  static double yaw(const geometry_msgs::Quaternion& q) {
    return std::atan2(2*(q.w*q.z+q.x*q.y), 1-2*(q.y*q.y+q.z*q.z));
  }
  static double wrap(double a) { return std::atan2(std::sin(a), std::cos(a)); }
  static Eigen::Isometry3d pose(const nav_msgs::Odometry& m) {
    Eigen::Isometry3d t = Eigen::Isometry3d::Identity();
    const auto& p=m.pose.pose.position; const auto& q=m.pose.pose.orientation;
    Eigen::Quaterniond orientation(q.w,q.x,q.y,q.z);
    if (!std::isfinite(orientation.norm()) || orientation.norm()<0.5)
      throw std::runtime_error("Invalid odometry orientation");
    t.linear()=orientation.normalized().toRotationMatrix(); t.translation()=V3(p.x,p.y,p.z);
    if (!t.matrix().allFinite()) throw std::runtime_error("Non-finite odometry");
    return t;
  }
  Eigen::Isometry3d vioBodyPose() const {
    auto body=pose(vio_);
    Eigen::Matrix3d optical_from_body;
    optical_from_body << 0,-1,0, 0,0,-1, 1,0,0;
    body.linear()=body.linear()*optical_from_body;
    return body;
  }
  V3 world(const V3& p) const { return slam_from_vio_*p; }
  V3 local(const V3& p) const { return slam_from_vio_.inverse()*p; }
  double worldYaw(double local_yaw) const {
    const V3 direction=slam_from_vio_.linear()*V3(std::cos(local_yaw),std::sin(local_yaw),0);
    return std::atan2(direction.y(),direction.x());
  }
  double localYaw(double world_yaw) const {
    const auto& r=slam_from_vio_.linear();
    const double c=std::cos(world_yaw),s=std::sin(world_yaw);
    return std::atan2(-r(1,0)*c+r(0,0)*s,r(1,1)*c-r(0,1)*s);
  }
  void status(const std::string& text) {
    status_=text; std_msgs::String m; m.data=text; status_pub_.publish(m);
    ROS_INFO_STREAM("[PlanningPreview] " << text);
  }
  void fail(const std::string& text) {
    state_=FAILED; paused_=false; status("FAILED: "+text); draw();
  }
  bool safetyEnabled() const {
    bool only=false; nh_.getParam("fsm/planning_only",only); return only;
  }
  void snapshot() {
    planner_.usePreviewSnapshot(nh_);
    ViewNode::map_=planner_.edt_environment_->occ_map_;
    ViewNode::astar_.reset(new Astar); ViewNode::astar_->init(nh_,planner_.edt_environment_);
    V3 origin,size; ViewNode::map_->getRegion(origin,size);
    ViewNode::caster_.reset(new RayCaster);
    ViewNode::caster_->setParams(ViewNode::map_->getResolution(),origin);
    frontier_.reset(new FrontierFinder(planner_.edt_environment_,nh_));
    planner_.setFrontier(frontier_);
    pcl::PointCloud<pcl::PointXYZ> cloud;
    ViewNode::map_->genPointCloud(cloud,-1e6,1e6,"world");
    if (cloud.empty()) throw std::runtime_error("Map is empty; scan the scene before start");
    sensor_msgs::PointCloud2 msg; pcl::toROSMsg(cloud,msg);msg.header.frame_id="world";
    map_pub_.publish(msg);
  }
  bool start(std_srvs::Trigger::Request&,std_srvs::Trigger::Response& res) {
    if (state_==WAIT_TOUR || state_==PLAN || state_==PLAY) {
      res.message="Preview already active; use pause/resume/stop";return true;
    }
    if (!safetyEnabled()) {res.message="fsm/planning_only must be true";return true;}
    if (!have_vio_ || !have_slam_ || (ros::Time::now()-vio_.header.stamp).toSec()>1 ||
        (ros::Time::now()-slam_.header.stamp).toSec()>1 ||
        std::abs((vio_.header.stamp-slam_.header.stamp).toSec())>0.3) {
      res.message="Fresh, time-aligned VINS and SLOAM odometry required";return true;
    }
    try {
      slam_from_vio_=pose(slam_)*vioBodyPose().inverse();
      if(slam_from_vio_.linear().topLeftCorner<2,2>().determinant()<0.1)
        throw std::runtime_error("SLAM/VIO transform has excessive tilt for yaw preview");
      virtual_state_.setZero();virtual_state_.col(0)=pose(vio_).translation();
      const auto body=vioBodyPose();
      virtual_yaw_=V3(std::atan2(body.linear()(1,0),body.linear()(0,0)),0,0);
      history_.clear();segment_.clear();goals_.clear();goal_yaws_.clear();
      candidates_.clear();candidate_yaws_.clear();frontiers_.clear();
      goal_index_=0;segments_=stalls_=0;paused_=false;
      snapshot();
      const V3 start_world=world(virtual_state_.col(0));
      if (!ViewNode::map_->isInBox(start_world) ||
          !planner_.edt_environment_local_->occ_map_->isInBox(V3(virtual_state_.col(0))))
        throw std::runtime_error("Start outside map boundary");
      if(planner_.edt_environment_local_->occ_map_->getInflateOccupancy(V3(virtual_state_.col(0)))==SDFMap::OCCUPIED)
        throw std::runtime_error("Start inside inflated obstacle; move the real camera clear, then start a new snapshot");
      history_={start_world};
      frontier_->searchFrontiers();frontier_->computeFrontiersToVisitIGNoPred();
      frontier_->updateFrontierCostMatrix();frontier_->getFrontiers(frontiers_);
      std::vector<V3> averages;std::vector<int> gains;
      const double world_yaw=yaw(slam_.pose.pose.orientation);
      frontier_->getTopViewpointsIGNoPred(start_world,candidates_,candidate_yaws_,averages,gains);
      if(candidates_.empty()) throw std::runtime_error("No coverable frontier in snapshot");
      if(candidates_.size()==1) {
        goals_=candidates_;goal_yaws_=candidate_yaws_;state_=PLAN;status("PLAN: fixed single viewpoint");
      } else {
        if(!cop_->isServerConnected()) throw std::runtime_error("Global COP server unavailable");
        frontier_->copyFrontierToPlanning();
        Eigen::MatrixXd costs;std::vector<std::vector<double>> correlations;
        frontier_->getFullCostMatrix(start_world,V3::Zero(),V3(world_yaw,0,0),costs);
        frontier_->getCorrelationMatrix(start_world,world_yaw,correlations);
        const int n=costs.rows();
        if(n!=static_cast<int>(candidates_.size())+1 || costs.cols()!=n || !costs.allFinite() ||
           correlations.size()!=static_cast<size_t>(n)) throw std::runtime_error("Invalid COP matrices");
        exploration_msgs::PlanCOPGoal goal;goal.header.stamp=ros::Time::now();goal.mat_size=n;
        goal.problem_size=std::min(11,n);goal.info_gain.push_back(0);
        for(int gain:gains)goal.info_gain.push_back(gain);
        if(goal.info_gain.size()!=static_cast<size_t>(n)) throw std::runtime_error("Invalid COP gains");
        for(int i=0;i<n;++i) {
          if(correlations[i].size()!=static_cast<size_t>(n)) throw std::runtime_error("Invalid correlation row");
          for(int j=0;j<n;++j){goal.cost_mat.push_back(costs(i,j));goal.correlation_mat.push_back(correlations[i][j]);}
        }
        goal.budget=0;for(int i=0;i<goal.problem_size;++i)goal.budget+=3*goal.cost_mat[i];
        cop_->sendGoal(goal);request_time_=ros::WallTime::now();state_=WAIT_TOUR;
        status("WAIT_TOUR: map and odometry transform captured");
      }
      res.success=true;res.message="Snapshot captured; preview started. No UAV execution.";draw();
    } catch(const std::exception& e) {fail(e.what());res.message=e.what();}
    return true;
  }
  bool pause(std_srvs::Trigger::Request&,std_srvs::Trigger::Response& res) {
    res.success=state_==PLAY || state_==PLAN || state_==WAIT_TOUR;
    if(res.success){paused_=true;status("PAUSED: virtual playback only");draw();}
    res.message=res.success?"Paused":"No active preview";return true;
  }
  bool resume(std_srvs::Trigger::Request&,std_srvs::Trigger::Response& res) {
    res.success=paused_ && safetyEnabled();
    if(res.success){paused_=false;last_tick_=ros::WallTime::now();status("RESUMED: virtual playback only");}
    res.message=res.success?"Resumed":"Not paused or planning_only is false";return true;
  }
  bool stop(std_srvs::Trigger::Request&,std_srvs::Trigger::Response& res) {
    if(state_==WAIT_TOUR) { cop_->cancelGoal(); }
    state_=IDLE;paused_=false;
    status("STOPPED: displays retained; start captures a new snapshot");draw();
    res.success=true;res.message="Stopped without UAV execution";return true;
  }
  bool reached() const {
    return (world(virtual_state_.col(0))-goals_[goal_index_]).norm()<=position_tolerance_ &&
      std::abs(wrap(worldYaw(virtual_yaw_(0))-goal_yaws_[goal_index_]))<=yaw_tolerance_;
  }
  bool validTrajectory() {
    auto& tr=planner_.local_data_.traj_;auto map=planner_.edt_environment_local_->occ_map_;
    const double duration=tr.getTotalDuration();
    if(tr.is_empty() || !std::isfinite(duration) || duration<=0)return false;
    // Dense sampled validation, including both endpoints. Use the existing occupancy policy.
    for(double t=0;;t=std::min(t+0.01,duration)) {
      V3 p=tr.getPos(t);
      if(!p.allFinite() || !map->isInMap(p) || !map->isInBox(p) || map->getInflateOccupancy(p)==SDFMap::OCCUPIED)return false;
      if(t>=duration)break;
    }
    return true;
  }
  void plan() {
    if(goal_index_>=goals_.size()){state_=FINISHED;status("FINISHED: all selected targets reached virtually");return;}
    if(reached()) {++goal_index_;stalls_=0;return;}
    if(segments_>=max_segments_){fail("Segment limit reached before original target");return;}
    const V3 goal=local(goals_[goal_index_]);
    segment_start_=virtual_state_.col(0);
    const bool rotation_only=(goal-segment_start_).norm()<=position_tolerance_;
    double desired_yaw=virtual_yaw_(0);
    if(rotation_only) {
      // Final orientation is previewed in place. Duration follows existing yaw limits.
      desired_yaw=virtual_yaw_(0)+wrap(localYaw(goal_yaws_[goal_index_])-virtual_yaw_(0));
      const double angle=std::abs(desired_yaw-virtual_yaw_(0));
      double max_acc=0;nh_.getParam("manager/max_ddyaw",max_acc);
      const double duration=1.1*std::max(1.875*angle/planner_.pp_.max_dyaw_,std::sqrt(5.774*angle/max_acc));
      if(!std::isfinite(duration) || duration<=0){fail("Invalid rotation duration");return;}
      Piece<5>::CoefficientMat c=Piece<5>::CoefficientMat::Zero();c.col(5)=segment_start_;
      planner_.local_data_.traj_.clear();planner_.local_data_.traj_.emplace_back(duration,c);
      planner_.local_data_.duration_=duration;
    } else {
      double heading=virtual_yaw_(0);
      Eigen::MatrixXd start_state=virtual_state_;
      if(!planner_.planExploreTrajGcopter(goal,start_state,heading)){fail("Local position planning failed; target retained");return;}
    }
    if(!validTrajectory()){fail("Trajectory leaves snapshot or intersects inflated occupancy");return;}
    // Translation holds heading; final viewpoint orientation is previewed separately in place.
    if(!planner_.planYawNoExplore(virtual_yaw_,desired_yaw,false,0)){
      fail("Yaw planning failed; limits unchanged, target retained");return;
    }
    auto& tr=planner_.local_data_.traj_;const double duration=tr.getTotalDuration();
    segment_.clear();for(double t=0;t<duration;t+=0.02)segment_.push_back(world(tr.getPos(t)));
    segment_.push_back(world(tr.getPos(duration)));
    if(!rotation_only && (tr.getPos(duration)-segment_start_).norm()<0.01) {
      if(++stalls_>=3){fail("No progress for three segments; original target not removed");return;}
    } else stalls_=0;
    ++segments_;elapsed_=0;last_tick_=ros::WallTime::now();state_=PLAY;
    status("PLAY: target "+std::to_string(goal_index_+1)+"/"+std::to_string(goals_.size())+
      ", segment "+std::to_string(segments_)+(rotation_only?", rotate in place":", translate"));
  }
  Marker marker(const std::string& ns,int type,float r,float g,float b) const {
    Marker m;m.header.frame_id="world";m.header.stamp=ros::Time::now();m.ns=ns;m.id=0;
    m.type=type;m.action=Marker::ADD;m.pose.orientation.w=1;m.color.r=r;m.color.g=g;m.color.b=b;m.color.a=1;
    m.scale.x=m.scale.y=m.scale.z=0.1;return m;
  }
  static void points(Marker& m,const std::vector<V3>& ps) {
    for(const auto& p:ps){geometry_msgs::Point q;q.x=p.x();q.y=p.y();q.z=p.z();m.points.push_back(q);}
  }
  void draw() {
    visualization_msgs::MarkerArray array;
    auto tour=marker("global_tour",Marker::LINE_STRIP,0,0.6,0);tour.scale.x=0.04;points(tour,goals_);array.markers.push_back(tour);
    auto views=marker("viewpoints",Marker::SPHERE_LIST,0,0.6,0);views.scale.x=views.scale.y=views.scale.z=0.18;points(views,candidates_);array.markers.push_back(views);
    auto frontier=marker("frontiers",Marker::CUBE_LIST,0.7,0.3,0.7);frontier.scale.x=frontier.scale.y=frontier.scale.z=0.05;
    for(const auto& f:frontiers_) { points(frontier,f); }
    array.markers.push_back(frontier);
    auto path=marker("local_trajectory",Marker::LINE_STRIP,0,0.5,1);path.scale.x=0.06;points(path,segment_);array.markers.push_back(path);
    auto history=marker("virtual_history",Marker::LINE_STRIP,0.45,0.45,0.45);history.scale.x=0.04;points(history,history_);array.markers.push_back(history);
    auto goal=marker("original_goal",Marker::SPHERE,1,0,0);goal.scale.x=goal.scale.y=goal.scale.z=0.25;
    if(goal_index_<goals_.size()){goal.pose.position.x=goals_[goal_index_].x();goal.pose.position.y=goals_[goal_index_].y();goal.pose.position.z=goals_[goal_index_].z();}else goal.action=Marker::DELETE;
    array.markers.push_back(goal);
    auto endpoint=marker("segment_endpoint",Marker::SPHERE,1,0.5,0);endpoint.scale.x=endpoint.scale.y=endpoint.scale.z=0.18;
    if(!segment_.empty()){endpoint.pose.position.x=segment_.back().x();endpoint.pose.position.y=segment_.back().y();endpoint.pose.position.z=segment_.back().z();}else endpoint.action=Marker::DELETE;
    array.markers.push_back(endpoint);
    V3 p=world(virtual_state_.col(0));
    auto camera=marker("virtual_camera",Marker::ARROW,0.1,0.2,0.9);camera.scale.x=0.5;camera.scale.y=0.12;camera.scale.z=0.12;
    camera.pose.position.x=p.x();camera.pose.position.y=p.y();camera.pose.position.z=p.z();
    Eigen::Quaterniond q(slam_from_vio_.linear()*Eigen::AngleAxisd(virtual_yaw_(0),V3::UnitZ()).toRotationMatrix());
    camera.pose.orientation.x=q.x();camera.pose.orientation.y=q.y();camera.pose.orientation.z=q.z();camera.pose.orientation.w=q.w();
    if(history_.empty()) { camera.action=Marker::DELETE; }
    array.markers.push_back(camera);
    auto label=marker("status",Marker::TEXT_VIEW_FACING,0.1,0.1,0.1);label.scale.z=0.16;
    label.pose.position.x=p.x();label.pose.position.y=p.y();label.pose.position.z=p.z()+0.7;
    label.text="SIMULATED PREVIEW - NO UAV EXECUTION\n"+status_;
    if(goal_index_<goals_.size()){std::ostringstream s;s.precision(2);s<<std::fixed<<(p-goals_[goal_index_]).norm();label.text+="\nDistance to original goal: "+s.str()+" m";}
    array.markers.push_back(label);markers_pub_.publish(array);
  }
  void tick(const ros::WallTimerEvent&) {
    if(!safetyEnabled()){if(state_==PLAN||state_==PLAY||state_==WAIT_TOUR)fail("planning_only was disabled");return;}
    if(paused_)return;
    try {
      if(state_==WAIT_TOUR) {
        if(cop_->getState().isDone()) {
          auto result=cop_->getResult();
          if(cop_->getState()!=actionlib::SimpleClientGoalState::SUCCEEDED || !result || !result->success){fail("Global COP failed");return;}
          std::set<int> selected;
          for(int index:result->sequence) {
            if(index==0)continue;
            if(index<1 || index>static_cast<int>(candidates_.size())){fail("Invalid COP target index");return;}
            if(selected.insert(index).second){goals_.push_back(candidates_[index-1]);goal_yaws_.push_back(candidate_yaws_[index-1]);}
          }
          if(goals_.empty()){fail("Empty Global Tour");return;}
          if(max_goals_>0 && goals_.size()>static_cast<size_t>(max_goals_)){goals_.resize(max_goals_);goal_yaws_.resize(max_goals_);}
          state_=PLAN;status("PLAN: fixed Global Tour received");
        }else if((ros::WallTime::now()-request_time_).toSec()>20){cop_->cancelGoal();fail("Global COP timed out");}
      }else if(state_==PLAN)plan();
      else if(state_==PLAY) {
        const auto now=ros::WallTime::now();elapsed_+=(now-last_tick_).toSec()*playback_speed_;last_tick_=now;
        auto& data=planner_.local_data_;const double t=std::min(elapsed_,data.duration_);
        virtual_state_.col(0)=data.traj_.getPos(t);virtual_state_.col(1)=data.traj_.getVel(t);virtual_state_.col(2)=data.traj_.getAcc(t);
        virtual_yaw_=V3(data.yaw_traj_.getPos(t),data.yaw_traj_.getVel(t),data.yaw_traj_.getAcc(t));
        history_.push_back(world(virtual_state_.col(0)));
        if(elapsed_>=data.duration_)state_=PLAN;
      }
      draw();
    }catch(const std::exception& e){fail(e.what());}
  }
public:
  explicit PlanningPreview(ros::NodeHandle nh):nh_(nh) {
    if(!safetyEnabled())throw std::runtime_error("Preview requires fsm/planning_only=true");
    nh_.param("preview/max_segments",max_segments_,100);nh_.param("preview/max_goals",max_goals_,0);
    nh_.param("preview/playback_speed",playback_speed_,1.0);
    nh_.param("preview/position_tolerance",position_tolerance_,0.15);nh_.param("preview/yaw_tolerance",yaw_tolerance_,0.1);
    if(max_segments_<1 || max_goals_<0 || playback_speed_<=0 || !std::isfinite(playback_speed_) || position_tolerance_<=0 || yaw_tolerance_<=0)
      throw std::runtime_error("Invalid preview parameters");
    if(!nh_.param<bool>("map_ros/vio_orientation_is_optical",false))
      throw std::runtime_error("D435i preview requires its optical-to-body mapper setting");
    planner_.initPlanModules(nh_);vis_.reset(new PlanningVisualization(nh_));planner_.setPlanVis(vis_);
    for(const auto& item:std::vector<std::pair<std::string,double*>>{{"vm",&ViewNode::vm_},{"am",&ViewNode::am_},{"yd",&ViewNode::yd_},{"ydd",&ViewNode::ydd_},{"w_dir",&ViewNode::w_dir_}})
      nh_.getParam("exploration/"+item.first,*item.second);
    vio_sub_=nh_.subscribe<nav_msgs::Odometry>("/odom_vio",1,[this](const nav_msgs::Odometry::ConstPtr& m){vio_=*m;have_vio_=true;});
    slam_sub_=nh_.subscribe<nav_msgs::Odometry>("/odom_slam",1,[this](const nav_msgs::Odometry::ConstPtr& m){slam_=*m;have_slam_=true;});
    markers_pub_=nh_.advertise<visualization_msgs::MarkerArray>("/planning_preview/markers",1,true);
    map_pub_=nh_.advertise<sensor_msgs::PointCloud2>("/planning_preview/map_snapshot",1,true);
    status_pub_=nh_.advertise<std_msgs::String>("/planning_preview/status",1,true);
    cop_.reset(new COP(nh_,"/exploration/global_plan_server",false));
    start_srv_=nh_.advertiseService("start",&PlanningPreview::start,this);
    pause_srv_=nh_.advertiseService("pause",&PlanningPreview::pause,this);
    resume_srv_=nh_.advertiseService("resume",&PlanningPreview::resume,this);
    stop_srv_=nh_.advertiseService("stop",&PlanningPreview::stop,this);
    timer_=nh_.createWallTimer(ros::WallDuration(0.05),&PlanningPreview::tick,this);
    status("IDLE: scan map, then call /planning_preview_node/start");
  }
};
} // namespace
int main(int argc,char** argv) {
  ros::init(argc,argv,"planning_preview_node");ros::NodeHandle nh("~");
  try{ms_planner::PlanningPreview preview(nh);ros::spin();}
  catch(const std::exception& e){ROS_FATAL_STREAM(e.what());return 1;}return 0;
}
