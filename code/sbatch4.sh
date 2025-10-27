#!/bin/bash

#SBATCH --job-name=llama-finetune
#SBATCH --nodes=2
#SBATCH -D .
#SBATCH --output=logs/O-%x_%j.txt
#SBATCH --error=logs/E-%x_%j.txt
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --export=ALL


# export NCCL_IB_DISABLE=1
# export NCCL_SOCKET_IFNAME=eth0
# export NCCL_DEBUG=WARN

# export NCCL_IB_DISABLE=None
# export NCCL_SOCKET_IFNAME=None
# export NCCL_DEBUG=None

mkdir -p logs

export OMP_NUM_THREADS=24
cd $SLURM_SUBMIT_DIR

export MASTER_PORT=12345
export WORLD_SIZE=$SLURM_NNODES
echo "WORLD_SIZE="$WORLD_SIZE

master_addr=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n 1)
export MASTER_ADDR=$master_addr
echo "MASTER_ADDR="$MASTER_ADDR

start_ts="$(date '+%Y-%m-%d %H:%M:%S')"
SECONDS=0
finish() {
  local elapsed=$SECONDS
  printf "Job started: %s\nJob ended:   %s\nElapsed:     %02d:%02d:%02d\n" \
    "$start_ts" "$(date '+%Y-%m-%d %H:%M:%S')" $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60))
}
trap finish EXIT

# srun srun.sh
# srun python multinode.py 100 5
# srun python simple_ddp.py
# srun singularity exec --nv $HOME/pytorch_containers/pytorch.sif python simple_ddp.py
# srun --container-image="$HOME/pytorch_containers/pytorch.sqsh" python simple_ddp.py

# srun --container-image="$HOME/pytorch_containers/pytorch.sqsh" \
#     bash -lc "python $SLURM_SUBMIT_DIR/simple_ddp.py"

# srun --container-image="$HOME/pytorch_containers/pytorch.sqsh" \
#      --container-mounts="$SLURM_SUBMIT_DIR:/workspace" \
#      -- bash -lc 'python /workspace/simple_ddp.py'

# finish() {
#   ec=$?
#   printf "Job exit code: %s\n" "$ec"
#   if [ "$ec" -eq 0 ]; then
#     echo "✅ JOB SUCCESS"
#   else
#     echo "❌ JOB FAILED"
#   fi
# }
# trap finish EXIT

_job_rc=0
finish() {
  local rc=${_job_rc:-$?}
  local elapsed=$SECONDS
  printf "\nJob started: %s\nJob ended:   %s\nElapsed:     %02d:%02d:%02d\n" \
    "$start_ts" "$(date '+%Y-%m-%d %H:%M:%S')" $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60))
  printf "Job exit code: %s\n" "$rc"
  if [ "$rc" -eq 0 ]; then
    echo "✅ JOB SUCCESS"
  else
    echo "❌ JOB FAILED"
  fi
}
trap finish EXIT

srun --container-image="$HOME/test-gpu-v8/docker2/custom-pytorch-cu128.sqsh" \
    -- bash -lc 'python3 /workspace/simple_ddp.py'

_job_rc=$?
if [ "$_job_rc" -eq 0 ]; then
  echo "PASSED" > "$SLURM_SUBMIT_DIR/test_result.txt"
  touch "$SLURM_SUBMIT_DIR/image_ready.flag"
else
  echo "FAILED" > "$SLURM_SUBMIT_DIR/test_result.txt"
  # exit with non-zero so SLURM shows failure
  exit $_job_rc
fi

# srun --container-image="$HOME/test-gpu-v8/docker2/custom-pytorch-cu128.sqsh" \
#     --container-mounts="$SLURM_SUBMIT_DIR/docker2:/workspace" \
#     -- bash -lc 'python3 /workspace/simple_ddp2.py'
