// Run with an existing ROS master. No topics, services or vehicle commands are published.
#include <plan_env/sdf_map.h>
#include <ros/ros.h>
#include <iostream>
#include <stdexcept>

int main(int argc,char** argv) {
  ros::init(argc,argv,"preview_snapshot_check",ros::init_options::AnonymousName);
  ros::NodeHandle nh;
  using namespace ms_planner;
  auto params=std::make_shared<MapParam>();
  params->resolution_=0.2;
  params->map_origin_=Eigen::Vector3d::Zero();params->map_size_=Eigen::Vector3d::Ones()*2;
  params->map_min_boundary_=params->map_origin_;params->map_max_boundary_=params->map_size_;
  params->box_mind_=params->map_min_boundary_;params->box_maxd_=params->map_max_boundary_;
  params->map_update_bound_inflate_=0.2;params->p_hit_=0.7;params->p_miss_=0.35;
  params->p_min_=0.12;params->p_max_=0.97;params->p_occ_=0.8;
  params->decay_amount_lower_than_occ_=0.1;params->set_no_flight_zone_=false;
  params->inflation_xy_=0.2;params->inflation_z_=0;params->decay_times_to_empty_=0;
  auto data=std::make_shared<MapData>();SDFMap live;live.initMap(nh,params,data);
  const Eigen::Vector3d point(0.5,0.5,0.5);
  live.setOccupied(point,100);
  auto frozen=live.snapshot(nh);
  if(frozen->getInflateOccupancy(point)!=SDFMap::OCCUPIED)
    throw std::runtime_error("Snapshot lost inflated occupancy");
  live.setOccupied(point,0);
  if(frozen->getInflateOccupancy(point)!=SDFMap::OCCUPIED || live.getInflateOccupancy(point)!=SDFMap::FREE)
    throw std::runtime_error("Snapshot aliases live occupancy buffer");
  params->box_mind_=Eigen::Vector3d::Ones();
  if(!frozen->isInBox(point) || live.isInBox(point))
    throw std::runtime_error("Snapshot aliases live parameters");
  frozen->setOccupied(point,0);
  live.setOccupied(point,100);
  if(frozen->getInflateOccupancy(point)!=SDFMap::FREE)
    throw std::runtime_error("Live map aliases snapshot writes");
  Eigen::Matrix3d optical_from_body;
  optical_from_body << 0,-1,0, 0,0,-1, 1,0,0;
  const Eigen::Matrix3d raw = Eigen::AngleAxisd(0.3,Eigen::Vector3d::UnitZ()).toRotationMatrix();
  const Eigen::Matrix3d body = raw*optical_from_body;
  const Eigen::Matrix3d aligned = body*(raw*optical_from_body).transpose();
  if(!aligned.isApprox(Eigen::Matrix3d::Identity(),1e-10))
    throw std::runtime_error("Optical/body comparison introduces spurious world-frame rotation");
  std::cout<<"PASS: snapshot preserves occupancy and isolates data/parameters in both directions"<<std::endl;
  return 0;
}
