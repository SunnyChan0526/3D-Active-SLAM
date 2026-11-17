#include <exploration_manager/handheld_policy.h>
#include <cassert>
#include <limits>
#include <iostream>
int main() {
  using namespace ms_planner;
  assert(handheldClosureResult(handheldClosureTag(7,true),7)==1);
  assert(handheldClosureResult(handheldClosureTag(7,true),8)==0);
  assert(handheldClosureResult(handheldClosureTag(7,false),7)==-1);
  std::atomic<std::uint64_t> feedback{0};
  handheldStoreClosureFeedback(feedback,8,true);
  handheldStoreClosureFeedback(feedback,7,false);
  assert(handheldClosureResult(feedback.load(),8)==1);
  // Either paper threshold independently triggers COP; no simulated time input.
  assert(!handheldGlobalRefresh(.14, 0, 10, true));
  assert(handheldGlobalRefresh(.15, 0, 10, true));
  assert(handheldGlobalRefresh(0, 1, 10, true));
  assert(!handheldGlobalRefresh(0, 1, 11, true));
  assert(handheldGlobalRefresh(0, 0, 0, false));
  assert(!handheldGlobalRefresh(0, 0, 0, true));
  for (int elapsed_seconds = 0; elapsed_seconds < 600; ++elapsed_seconds)
    assert(!handheldGlobalRefresh(0, 0, 10, true));
  // Actual position AND actual heading are required for frontier observations.
  assert(handheldReached(.49, .19));
  assert(!handheldReached(.51, 0));
  assert(!handheldReached(.1, .21));
  assert(!handheldReached(std::numeric_limits<double>::quiet_NaN(), 0));
  assert(!handheldReached(.1, std::numeric_limits<double>::quiet_NaN()));
  std::cout << "Handheld feedback policy regression passed" << std::endl;
}
