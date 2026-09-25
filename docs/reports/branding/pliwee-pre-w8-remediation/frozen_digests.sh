#!/usr/bin/env bash
# G8 — frozen artefacts on the RC commit: the five Wave 0 masters (R4.2) and
# the two D10 DER vectors (Wave 5 §2). Exact count: 7 files, 7 matches.
# Exits 2 if a tool is missing, 1 on any mismatch or a missing file.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
command -v sha256sum >/dev/null || { echo "REFUSE: sha256sum absent"; exit 2; }
expected=(
  "b1d927564f25c8c59361eb3a7a5cad845ce18428421a053b25cbe1943440519c docs/design/assets/pliwee-mark.svg"
  "15120dd82ba288f51854baec6820f93f72d78bcc1d029451d3b88691cb510fdf docs/design/assets/pliwee-mark-mono.svg"
  "99201df067a31aed898f45d31b0d04a01e430a6d4f4e7c595357996428d7ee1b docs/design/assets/pliwee-mark-tonal.svg"
  "6220f2e8d275357f010c9456ca75bddfccfe25ea587969fa61933d4aeeafaf13 docs/design/assets/pliwee-wordmark.svg"
  "78792f3e978bdc97b7f16efbdcd92d08f9e1771f6ad5d674ff0c9ea0423245de docs/design/assets/pliwee-lockup.svg"
  "cdb976416b52d73b00faeadcb1890e35515061527559cd0643e451b7c46baa41 protocol/testdata/identity-a.der"
  "a3b55bf1b9db309585eec391efb5de42ca0cd3c4810ba03d4cc1986ce26561a8 protocol/testdata/identity-b.der"
)
pass=0 fail=0
for line in "${expected[@]}"; do
  want=${line%% *} path=${line#* }
  if [ ! -f "$path" ]; then echo "FAIL  $path  missing"; fail=$((fail+1)); continue; fi
  got=$(sha256sum -- "$path"); got=${got%% *}
  if [ "$got" = "$want" ]; then echo "PASS  $path  $got"; pass=$((pass+1))
  else echo "FAIL  $path  $got (want $want)"; fail=$((fail+1)); fi
done
echo "frozen digests: $pass passed, $fail failed (expected exactly ${#expected[@]} passed)"
[ "$fail" -eq 0 ] && [ "$pass" -eq "${#expected[@]}" ]
