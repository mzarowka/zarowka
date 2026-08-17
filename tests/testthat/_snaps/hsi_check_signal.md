# hsi_check_signal aborts with informative messages

    Code
      hsi_check_signal(x = test_capture, darkref = test_dark[[1:50]])
    Condition
      Error in `hsi_check_signal()`:
      ! `darkref` must have the same number of bands as `x`.
      x Sample: 101 bands
      x Dark reference: 50 bands

---

    Code
      hsi_check_signal(x = test_capture, darkref = test_dark, k = Inf)
    Condition
      Error in `hsi_check_signal()`:
      ! `k` must contain only finite values.

---

    Code
      hsi_check_signal(x = test_capture, darkref = test_dark, fraction = 1.5)
    Condition
      Error in `hsi_check_signal()`:
      ! `fraction` must be in the interval (0, 1], not 1.5.

