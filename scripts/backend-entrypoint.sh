#!/bin/sh
# Source: derived from fork260506-go-admin/Dockerfile.learning (001 分支) line 11-20
# 註:本 script 不設 GOPROXY/GOSUMDB(Taiwan 直連 proxy.golang.org / sum.golang.org)。
#    若在中國網路下,可在 docker-compose.yml 的 x-backend-base.environment 取消註解
#    GOPROXY=https://goproxy.cn,direct 與 GOSUMDB=sum.golang.google.cn。
set -e

# (1) CGO toolchain — sqlite 需 CGO,golang:1.24-alpine 沒 gcc。
#     `docker compose stop/start` 保留容器 → 不會重裝;
#     `docker compose down/up` 重建容器 → 會重裝(額外 ~30s 一次)。
command -v gcc >/dev/null 2>&1 || apk add --no-cache gcc g++ libc6-compat sqlite tzdata

cd /workspace/fork260506-go-admin

# (2) go.sum tidy fallback —
#     fork260506-go-admin/.gitignore 忽略 go.sum (參見 Dockerfile.learning:11-15 觀察),
#     bind-mount 進來時可能缺;只跑 `go mod download` 不夠 (Go 1.17+ 不會填 transitive go.sum)。
[ ! -f go.sum ] && go mod tidy

# (3) `go run` with sqlite3 build tag —
#     對應 Dockerfile.learning:20 的 `go build -tags sqlite3`;
#     mysql 變體不需要此 tag,但加上去也只是多 link 一個未用的驅動,無害。
exec go run -tags sqlite3 main.go "$@"
