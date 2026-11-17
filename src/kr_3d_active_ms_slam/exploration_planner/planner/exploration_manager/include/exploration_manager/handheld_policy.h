#pragma once
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <atomic>

namespace ms_planner {
inline std::uint64_t handheldClosureTag(std::size_t request, bool success) {
  return (std::uint64_t(request) << 2) | (success ? 1 : 2);
}
inline int handheldClosureResult(std::uint64_t tag, std::size_t request) {
  if ((tag >> 2) != request) return 0;
  return (tag & 3) == 1 ? 1 : ((tag & 3) == 2 ? -1 : 0);
}
inline void handheldStoreClosureFeedback(std::atomic<std::uint64_t>& feedback,
                                         std::size_t request, bool success) {
  const auto tag = handheldClosureTag(request, success);
  auto previous = feedback.load();
  while ((previous >> 2) <= request &&
         !feedback.compare_exchange_weak(previous, tag)) {}
}
// Pure feedback policy: elapsed trajectory time is deliberately not an input.
// unplanned_closure: SLC candidates exist now but the accepted tour was planned
// with none, so planActiveLoopClosurePath never saw them. One-shot by design:
// once a tour is planned with candidates, later id churn does not retrigger.
inline bool handheldGlobalRefresh(double frontier_change, std::size_t completed,
                                  std::size_t initial, bool remaining,
                                  bool unplanned_closure = false) {
  // Same as the author's drone rule (keep while change < 0.15 OR > 90% of the
  // tour remains): both thresholds are required. With OR, a hand-held camera
  // marks >15% of frontiers changed every second and COP re-ran at ~1 Hz.
  return !remaining || unplanned_closure ||
      (frontier_change >= 0.15 && initial > 0 &&
       static_cast<double>(completed) / initial >= 0.10);
}
inline bool handheldReached(double distance, double yaw_error) {
  return std::isfinite(distance) && std::isfinite(yaw_error) &&
      distance <= 0.5 && std::abs(yaw_error) <= 0.2;
}
}
