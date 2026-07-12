# Train a small Chinese character-level nanoGPT model.

out_dir = "out-zh-char"
eval_interval = 50
eval_iters = 20
log_interval = 10
always_save_checkpoint = True

wandb_log = False
wandb_project = "zh-char"
wandb_run_name = "mini-zh-gpt"

dataset = "zh_char"
gradient_accumulation_steps = 1
batch_size = 16
block_size = 64

n_layer = 2
n_head = 2
n_embd = 128
dropout = 0.1

learning_rate = 1e-3
max_iters = 500
lr_decay_iters = 500
min_lr = 1e-4
beta2 = 0.99
warmup_iters = 20

device = "cpu"
dtype = "float32"
compile = False
