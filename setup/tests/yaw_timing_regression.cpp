#include <plan_manage/planner_manager.h>
#include <cmath>
#include <stdexcept>

void require(bool condition, const char* reason) {
  if (!condition) throw std::runtime_error(reason);
}
void initialize(ms_planner::msPlannerManager& planner, double duration) {
  planner.pp_.max_dyaw_ = M_PI / 3 - .2;
  planner.kino_yaw_finder_.reset(new ms_planner::KinoYaw);
  Eigen::VectorXd weights(3), limits(2);
  weights << 40, 2000, 4000;
  limits << M_PI / 3, M_PI / 2;
  planner.poly_yaw_solver_.init(weights, limits);
  Piece<5>::CoefficientMat coefficients = Piece<5>::CoefficientMat::Zero();
  coefficients(0, 0) = 6 / std::pow(duration, 5);
  coefficients(0, 1) = -15 / std::pow(duration, 4);
  coefficients(0, 2) = 10 / std::pow(duration, 3);
  planner.local_data_.traj_.emplace_back(duration, coefficients);
  planner.local_data_.duration_ = duration;
}
int main() {
  ros::Time::init();
  const double duration = 1.88697;
  ms_planner::msPlannerManager planner;
  initialize(planner, duration);
  const auto original = planner.local_data_.traj_;
  require(planner.planYawNoExplore(Eigen::Vector3d(-1.32908, 0, 0), 2.01025, false),
          "recorded yaw failure should become feasible with more time");
  require(planner.local_data_.duration_ > duration, "failing case must extend time");
  require(std::abs(planner.local_data_.duration_ - planner.local_data_.yaw_duration_) < 1e-6,
          "position and yaw durations must match");
  require(planner.local_data_.yaw_traj_.getMaxVelRate() <= 1.3 * M_PI / 3 + 1e-6,
          "yaw velocity limit exceeded");
  require(planner.local_data_.yaw_traj_.getMaxAccRate() <= 1.3 * M_PI / 2 + 1e-6,
          "yaw acceleration limit exceeded");
  for (double t = 0; t <= duration; t += .05)
    require((planner.local_data_.traj_.getPos(t) - original.getPos(t)).norm() < 1e-8,
            "existing position path changed");
  const auto endpoint = original.getPos(duration);
  for (double t = duration; t <= planner.local_data_.duration_; t += .05) {
    require((planner.local_data_.traj_.getPos(t) - endpoint).norm() < 1e-8,
            "extra position suffix must hold endpoint");
    require(planner.local_data_.traj_.getVel(t).norm() < 1e-8, "suffix moves");
  }
  ms_planner::msPlannerManager feasible;
  initialize(feasible, duration);
  require(feasible.planYawNoExplore(Eigen::Vector3d::Zero(), .1, false), "small yaw failed");
  require(std::abs(feasible.local_data_.duration_ - duration) < 1e-8,
          "already feasible trajectory was extended");
  ms_planner::msPlannerManager moving_end;
  moving_end.pp_.max_dyaw_ = M_PI / 3 - .2;
  moving_end.kino_yaw_finder_.reset(new ms_planner::KinoYaw);
  Eigen::VectorXd weights(3), limits(2);
  weights << 40, 2000, 4000; limits << M_PI/3, M_PI/2;
  moving_end.poly_yaw_solver_.init(weights, limits);
  Piece<5>::CoefficientMat linear = Piece<5>::CoefficientMat::Zero();
  linear(0, 4) = .1;
  moving_end.local_data_.traj_.emplace_back(duration, linear);
  moving_end.local_data_.duration_ = duration;
  require(!moving_end.planYawNoExplore(Eigen::Vector3d(-1.32908,0,0),2.01025,false),
          "nonstationary endpoint must not acquire a discontinuous hold");
  require(moving_end.local_data_.traj_.getPieceNum() == 1,
          "failed retry mutated position path");
  std::cout << "Yaw timing regression passed; extended duration="
            << planner.local_data_.duration_ << std::endl;
}
