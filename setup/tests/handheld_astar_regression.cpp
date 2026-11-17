// Offline fixture for the actual A* search and the 10 cm occupancy map.
#include <Eigen/Eigen>
#include <Eigen/StdVector>
#include <ros/ros.h>
#include <pcl/point_cloud.h>
#include <pcl/point_types.h>
#include <queue>
#include <tuple>
#include <map>
#include <unordered_map>
#include <boost/functional/hash.hpp>
#include <plan_env/raycast.h>
#define private public
#include <plan_env/sdf_map.h>
#include <path_searching/astar2.h>
#undef private
#include <cassert>
#include <iostream>
using namespace ms_planner;
int main() {
  ros::Time::init();
  auto map = std::make_shared<SDFMap>();
  map->mp_ = std::make_shared<MapParam>();
  map->md_ = std::make_shared<MapData>();
  auto p=map->mp_; auto d=map->md_;
  p->resolution_=.1; p->resolution_inv_=10;
  p->map_origin_=p->map_min_boundary_=Eigen::Vector3d::Zero();
  p->map_size_=p->map_max_boundary_=Eigen::Vector3d(3,3,1);
  p->map_voxel_num_=Eigen::Vector3i(30,30,10);
  p->box_mind_=p->map_min_boundary_; p->box_maxd_=p->map_max_boundary_;
  p->clamp_min_log_=-2; p->min_occupancy_log_=1;
  d->occupancy_buffer_.assign(9000,-2);
  d->occupancy_buffer_inflate_.assign(9000,-2);
  auto env=std::make_shared<EDTEnvironment>();env->setMap(map);
  Astar astar;
  astar.edt_env_=env;astar.origin_=p->map_origin_;
  astar.allocate_num_=100000;astar.path_node_pool_.resize(astar.allocate_num_);
  for(auto& node:astar.path_node_pool_)node=new Node;
  astar.use_node_num_=0;astar.iter_num_=0;astar.tie_breaker_=1.001;
  astar.lambda_heu_=1;astar.max_search_time_=1;
  Eigen::Vector3d start(.25,1.45,.45),goal(2.75,1.45,.45);
  // Free map: both resolutions reach the target.
  for(double resolution: {.02,.1}) {
    astar.reset();astar.setResolution(resolution);
    assert(astar.search(start,goal)==Astar::REACH_END);
  }
  // Occupied slab with a doorway away from the direct line.
  for(int x=14;x<=15;++x)for(int y=0;y<30;++y)for(int z=0;z<10;++z) {
    if(y>=7 && y<=11)continue;
    int a=map->toAddress(x,y,z);d->occupancy_buffer_[a]=2;d->occupancy_buffer_inflate_[a]=2;
  }
  astar.reset();astar.setResolution(.1);
  assert(astar.search(start,goal)==Astar::REACH_END);
  auto path=astar.getPath();assert(path.size()>2);
  // Independently sample every returned segment finer than the map resolution.
  for(size_t i=1;i<path.size();++i) {
    const auto delta=(path[i]-path[i-1]).eval();
    int samples=std::max(1,int(std::ceil(delta.norm()/.005)));
    for(int j=0;j<=samples;++j) {
      Eigen::Vector3d q=path[i-1]+double(j)/samples*delta;
      assert(map->getInflateOccupancy(q)!=SDFMap::OCCUPIED);
    }
  }
  // Seal doorway: the faster grid may not fabricate a path through the wall.
  for(int x=14;x<=15;++x)for(int y=7;y<=11;++y)for(int z=0;z<10;++z) {
    int a=map->toAddress(x,y,z);d->occupancy_buffer_[a]=2;d->occupancy_buffer_inflate_[a]=2;
  }
  astar.reset();assert(astar.search(start,goal)==Astar::NO_PATH);
  std::cout<<"Actual A* regression passed: free map, doorway detour with dense collision sampling, sealed wall rejected."<<std::endl;
}
