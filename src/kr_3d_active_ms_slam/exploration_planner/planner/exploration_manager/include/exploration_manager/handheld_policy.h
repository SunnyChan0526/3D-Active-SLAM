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
inline bool handheldGlobalRefresh(double frontier_change, std::size_t completed,
                                  std::size_t initial, bool remaining) {
  return !remaining || frontier_change >= 0.15 ||
      (initial > 0 && static_cast<double>(completed) / initial >= 0.10);
}
inline bool handheldReached(double distance, double yaw_error) {
  return std::isfinite(distance) && std::isfinite(yaw_error) &&
      distance <= 0.5 && std::abs(yaw_error) <= 0.2;
}
}
