# LLM Learning Journey (M2 Pro Mac Mini)

## Overview

The M2 Pro Mac mini serves as a dedicated **AI research and learning platform** for training, fine-tuning, and evaluating domain-specific language models.

**Goals:**
1. Train a character-level transformer from scratch on Axinova documentation
2. Fine-tune Llama 3 8B on code generation tasks
3. Compare pre-training vs. fine-tuning performance
4. Understand LLM internals (tokenization, attention, training dynamics)
5. Build reusable training pipeline for future experiments

**Hardware:**
- Mac mini M2 Pro (10-core CPU, 16-core GPU, 32GB RAM)
- Local Ollama for inference
- ~200GB storage for models and datasets

---

## Phase 1: Character-Level Transformer from Scratch

**Duration:** 2-4 weeks

**Objective:** Train a tiny language model (2-layer transformer, ~1M parameters) on Axinova documentation corpus to understand training fundamentals.

### Step 1: Data Collection (2-3 days)

**Corpus Sources:**
- All `README.md`, `CLAUDE.md`, `docs/*.md` from Axinova repos
- SilverBullet wiki pages (runbooks, architecture)
- GitHub issues and PR descriptions
- Code comments from Go/Vue files

**Script:** `scripts/collect-corpus.py`

```python
import os
import glob

def collect_corpus():
    """Collect all Markdown and code comment text from Axinova repos"""
    corpus = []

    # Markdown files
    for md_file in glob.glob("/Users/weixia/axinova/**/*.md", recursive=True):
        with open(md_file) as f:
            corpus.append(f.read())

    # Go comments
    for go_file in glob.glob("/Users/weixia/axinova/**/*.go", recursive=True):
        with open(go_file) as f:
            comments = [line for line in f if line.strip().startswith("//")]
            corpus.extend(comments)

    # Save
    with open("corpus.txt", "w") as f:
        f.write("\n\n".join(corpus))

    print(f"Collected {len(corpus)} documents, {sum(len(d) for d in corpus)} characters")

if __name__ == "__main__":
    collect_corpus()
```

**Expected Output:**
- `corpus.txt`: ~500KB-1MB of text
- ~50,000-100,000 tokens (character-level)

---

### Step 2: Tokenizer Implementation (1-2 days)

**Approach:** Character-level tokenizer (simplest for learning)

**Script:** `scripts/tokenizer.py`

```python
class CharTokenizer:
    """Character-level tokenizer"""

    def __init__(self, corpus):
        chars = sorted(set(corpus))
        self.vocab_size = len(chars)
        self.char_to_idx = {ch: i for i, ch in enumerate(chars)}
        self.idx_to_char = {i: ch for i, ch in enumerate(chars)}

    def encode(self, text):
        return [self.char_to_idx[ch] for ch in text]

    def decode(self, indices):
        return "".join([self.idx_to_char[i] for i in indices])

# Example
with open("corpus.txt") as f:
    corpus = f.read()

tokenizer = CharTokenizer(corpus)
print(f"Vocabulary size: {tokenizer.vocab_size}")  # ~100-200 chars

# Test
encoded = tokenizer.encode("Hello, world!")
decoded = tokenizer.decode(encoded)
assert decoded == "Hello, world!"
```

**Advanced (Week 3-4):** Implement BPE (Byte-Pair Encoding) for better compression

---

### Step 3: Model Architecture (2-3 days)

**Architecture:** Tiny GPT-style transformer

```python
import torch
import torch.nn as nn

class TinyTransformer(nn.Module):
    """2-layer character-level transformer"""

    def __init__(self, vocab_size=200, d_model=128, n_heads=8, n_layers=2, max_len=512):
        super().__init__()
        self.embed = nn.Embedding(vocab_size, d_model)
        self.pos_embed = nn.Embedding(max_len, d_model)

        self.layers = nn.ModuleList([
            nn.TransformerEncoderLayer(d_model, n_heads, dim_feedforward=512, batch_first=True)
            for _ in range(n_layers)
        ])

        self.ln = nn.LayerNorm(d_model)
        self.head = nn.Linear(d_model, vocab_size)

    def forward(self, x):
        B, T = x.shape
        pos = torch.arange(T, device=x.device).unsqueeze(0).expand(B, T)

        x = self.embed(x) + self.pos_embed(pos)

        for layer in self.layers:
            x = layer(x)

        x = self.ln(x)
        logits = self.head(x)

        return logits

# Model stats
model = TinyTransformer()
total_params = sum(p.numel() for p in model.parameters())
print(f"Total parameters: {total_params:,}")  # ~1-2M parameters
```

---

### Step 4: Training Loop (3-5 days)

**Training Script:** `scripts/train.py`

```python
import torch
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from tqdm import tqdm

class TextDataset(Dataset):
    """Character-level dataset"""

    def __init__(self, corpus, tokenizer, max_len=512):
        self.data = tokenizer.encode(corpus)
        self.max_len = max_len

    def __len__(self):
        return len(self.data) - self.max_len

    def __getitem__(self, idx):
        chunk = self.data[idx:idx + self.max_len + 1]
        x = torch.tensor(chunk[:-1], dtype=torch.long)
        y = torch.tensor(chunk[1:], dtype=torch.long)
        return x, y

def train_epoch(model, dataloader, optimizer, device):
    model.train()
    total_loss = 0

    for x, y in tqdm(dataloader):
        x, y = x.to(device), y.to(device)

        logits = model(x)
        loss = F.cross_entropy(logits.view(-1, logits.size(-1)), y.view(-1))

        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        total_loss += loss.item()

    return total_loss / len(dataloader)

# Training
device = torch.device("mps")  # M2 Pro GPU
model = TinyTransformer().to(device)
optimizer = torch.optim.AdamW(model.parameters(), lr=3e-4)

dataset = TextDataset(corpus, tokenizer)
dataloader = DataLoader(dataset, batch_size=16, shuffle=True)

for epoch in range(10):
    loss = train_epoch(model, dataloader, optimizer, device)
    print(f"Epoch {epoch+1}/10, Loss: {loss:.4f}")

    # Save checkpoint
    torch.save(model.state_dict(), f"checkpoints/epoch_{epoch+1}.pt")
```

**Training Parameters:**
- Epochs: 10-20
- Batch size: 16-32
- Learning rate: 3e-4
- Expected time: 1-2 hours on M2 Pro GPU

---

### Step 5: Evaluation & Sampling (2-3 days)

**Metrics:**
1. **Perplexity:** How well model predicts next character
2. **Sample Quality:** Generate text and inspect coherence
3. **Loss Curve:** Track training/validation loss

**Evaluation Script:** `scripts/evaluate.py`

```python
import torch
import math

def evaluate(model, dataloader, device):
    model.eval()
    total_loss = 0

    with torch.no_grad():
        for x, y in dataloader:
            x, y = x.to(device), y.to(device)
            logits = model(x)
            loss = F.cross_entropy(logits.view(-1, logits.size(-1)), y.view(-1))
            total_loss += loss.item()

    avg_loss = total_loss / len(dataloader)
    perplexity = math.exp(avg_loss)

    return avg_loss, perplexity

# Run evaluation
loss, ppl = evaluate(model, val_dataloader, device)
print(f"Validation Loss: {loss:.4f}, Perplexity: {ppl:.2f}")
```

**Text Generation:**

```python
def generate(model, tokenizer, prompt, max_new_tokens=100, temperature=1.0):
    model.eval()
    device = next(model.parameters()).device

    # Encode prompt
    tokens = torch.tensor(tokenizer.encode(prompt), dtype=torch.long).unsqueeze(0).to(device)

    for _ in range(max_new_tokens):
        logits = model(tokens)
        logits = logits[:, -1, :] / temperature

        probs = F.softmax(logits, dim=-1)
        next_token = torch.multinomial(probs, num_samples=1)

        tokens = torch.cat([tokens, next_token], dim=1)

        # Stop if max length
        if tokens.size(1) >= model.pos_embed.num_embeddings:
            break

    return tokenizer.decode(tokens[0].tolist())

# Generate
prompt = "## Axinova "
generated = generate(model, tokenizer, prompt, max_new_tokens=200)
print(generated)
```

**Expected Output (after training):**
```
## Axinova Agent Fleet

The agent fleet consists of two teams running on Mac minis.
Each team specializes in different roles: backend, frontend, devops...
```

---

### Step 6: Analysis & Documentation (2-3 days)

**Document findings in SilverBullet wiki:**

```markdown
# LLM Experiment #1: Character-Level Transformer

## Setup
- Model: 2-layer transformer, 128 hidden dim, 8 heads
- Dataset: Axinova docs (~500KB text)
- Training: 10 epochs, batch size 16, lr 3e-4
- Hardware: M2 Pro GPU

## Results
- Final validation perplexity: 3.2
- Training time: 1.5 hours
- Model size: 1.2M parameters (5MB checkpoint)

## Samples
**Prompt:** "## Axinova "
**Output:** "Agent Fleet\n\nThe agent fleet consists of..."

## Learnings
- Character-level models are slow (small vocab but long sequences)
- Perplexity improved from 45 → 3.2 over 10 epochs
- Model memorizes common phrases (e.g., "# Agent Fleet", "GitHub Actions")
- Overfitting after epoch 7 (validation loss plateaus)

## Next Steps
- Implement BPE tokenizer (reduce sequence length)
- Add dropout for regularization
- Increase model size (4 layers, 256 hidden dim)
- Train on larger corpus (include code, not just docs)
```

---

## Phase 2: Fine-Tuning Llama 3 8B

**Duration:** 3-4 weeks

**Objective:** Fine-tune a pre-trained LLM (Llama 3 8B) on Axinova-specific code generation tasks and compare to training from scratch.

### Step 1: Setup Llama 3 8B (1-2 days)

**Download Model:**
```bash
# Install Ollama
brew install ollama

# Pull Llama 3 8B
ollama pull llama3:8b

# Verify
ollama run llama3:8b "Hello, world!"
```

**Convert to PyTorch for Fine-Tuning:**
```bash
# Install transformers
pip install transformers accelerate

# Load model
python -c "
from transformers import AutoModelForCausalLM, AutoTokenizer
model = AutoModelForCausalLM.from_pretrained('meta-llama/Meta-Llama-3-8B')
tokenizer = AutoTokenizer.from_pretrained('meta-llama/Meta-Llama-3-8B')
print(f'Model loaded: {model.num_parameters():,} parameters')
"
```

---

### Step 2: Prepare Fine-Tuning Dataset (2-3 days)

**Task:** Code generation for Axinova microservices

**Dataset Format:** Instruction-following pairs

```json
[
  {
    "instruction": "Write a Go API endpoint to create a new project",
    "input": "POST /v1/projects with JSON body: {\"name\": \"My Project\", \"description\": \"...\"}",
    "output": "func CreateProject(w http.ResponseWriter, r *http.Request) {\n\tvar req CreateProjectRequest\n\tif err := json.NewDecoder(r.Body).Decode(&req); err != nil {\n\t\thttp.Error(w, err.Error(), http.StatusBadRequest)\n\t\treturn\n\t}\n\t// Save to database...\n}"
  },
  {
    "instruction": "Write a Vue 3 component to display a project card",
    "input": "Props: { project: { id: number, name: string, description: string } }",
    "output": "<template>\n  <div class=\"project-card\">\n    <h3>{{ project.name }}</h3>\n    <p>{{ project.description }}</p>\n  </div>\n</template>\n\n<script setup lang=\"ts\">\ndefineProps<{\n  project: { id: number; name: string; description: string }\n}>()\n</script>"
  }
]
```

**Generation Script:** Extract code patterns from existing repos

```python
import os
import json
import re

def extract_code_examples():
    """Extract instruction-output pairs from Axinova repos"""
    examples = []

    # Find Go API handlers
    for go_file in glob.glob("/Users/weixia/axinova/**/internal/api/*.go", recursive=True):
        with open(go_file) as f:
            content = f.read()

            # Extract handler functions
            handlers = re.findall(r'func (\w+)\(w http\.ResponseWriter.*?\n(.*?)\n}', content, re.DOTALL)

            for name, body in handlers:
                examples.append({
                    "instruction": f"Write a Go API handler for {name}",
                    "input": f"HTTP handler signature: func {name}(w http.ResponseWriter, r *http.Request)",
                    "output": f"func {name}(w http.ResponseWriter, r *http.Request) {{\n{body}\n}}"
                })

    # Find Vue components
    for vue_file in glob.glob("/Users/weixia/axinova/**/src/components/*.vue", recursive=True):
        with open(vue_file) as f:
            content = f.read()

            component_name = os.path.basename(vue_file).replace(".vue", "")
            examples.append({
                "instruction": f"Write a Vue 3 component for {component_name}",
                "input": f"Component name: {component_name}",
                "output": content
            })

    # Save dataset
    with open("fine-tune-dataset.json", "w") as f:
        json.dump(examples, f, indent=2)

    print(f"Extracted {len(examples)} code examples")

extract_code_examples()
```

**Expected Dataset Size:** 100-500 examples

---

### Step 3: LoRA Fine-Tuning (3-5 days)

**Use LoRA (Low-Rank Adaptation) for efficient fine-tuning**

```python
from transformers import AutoModelForCausalLM, AutoTokenizer, TrainingArguments, Trainer
from peft import get_peft_model, LoraConfig, TaskType
from datasets import load_dataset

# Load model
model = AutoModelForCausalLM.from_pretrained("meta-llama/Meta-Llama-3-8B", device_map="auto")
tokenizer = AutoTokenizer.from_pretrained("meta-llama/Meta-Llama-3-8B")

# LoRA config
lora_config = LoraConfig(
    task_type=TaskType.CAUSAL_LM,
    r=8,  # Low-rank dimension
    lora_alpha=32,
    lora_dropout=0.1,
    target_modules=["q_proj", "v_proj"]  # Apply LoRA to attention layers
)

model = get_peft_model(model, lora_config)
model.print_trainable_parameters()  # Only ~0.1% of parameters are trainable

# Load dataset
dataset = load_dataset("json", data_files="fine-tune-dataset.json")

# Tokenize
def tokenize_function(examples):
    prompts = [f"Instruction: {inst}\nInput: {inp}\nOutput: " for inst, inp in zip(examples["instruction"], examples["input"])]
    outputs = examples["output"]

    model_inputs = tokenizer(prompts, max_length=512, truncation=True, padding="max_length")
    labels = tokenizer(outputs, max_length=512, truncation=True, padding="max_length")["input_ids"]

    model_inputs["labels"] = labels
    return model_inputs

tokenized_dataset = dataset.map(tokenize_function, batched=True)

# Training arguments
training_args = TrainingArguments(
    output_dir="./lora-llama3-axinova",
    num_train_epochs=3,
    per_device_train_batch_size=1,  # M2 Pro GPU memory constraint
    gradient_accumulation_steps=8,
    learning_rate=3e-4,
    logging_steps=10,
    save_steps=100,
    save_total_limit=2,
)

# Train
trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized_dataset["train"],
)

trainer.train()

# Save LoRA weights
model.save_pretrained("./lora-llama3-axinova-final")
```

**Training Time:** 2-4 hours on M2 Pro GPU

---

### Step 4: Evaluation & Comparison (2-3 days)

**Compare Models:**
1. **Baseline Llama 3 8B:** No fine-tuning
2. **Fine-tuned Llama 3 8B:** LoRA fine-tuned on Axinova code
3. **Tiny Transformer:** Trained from scratch (Phase 1)

**Evaluation Tasks:**
- Code completion accuracy
- Instruction following (ROUGE-L score)
- Human evaluation (5-point scale)

```python
# Evaluation script
def evaluate_models():
    test_prompts = [
        "Write a Go API handler to list all projects",
        "Create a Vue component for a user profile card",
        "Implement database migration for adding 'status' column to projects table"
    ]

    results = {}

    for model_name, model in [("baseline", baseline_model), ("fine-tuned", finetuned_model), ("tiny", tiny_model)]:
        outputs = []
        for prompt in test_prompts:
            output = generate(model, prompt)
            outputs.append(output)

        results[model_name] = outputs

    # Compare
    for prompt, outputs in zip(test_prompts, zip(*results.values())):
        print(f"\nPrompt: {prompt}")
        for model_name, output in zip(results.keys(), outputs):
            print(f"\n{model_name}:\n{output}\n")
```

---

### Step 5: Documentation & Insights (2-3 days)

**Wiki Documentation:**

```markdown
# LLM Experiment #2: Fine-Tuning Llama 3 8B

## Setup
- Base model: Llama 3 8B (8 billion parameters)
- Fine-tuning: LoRA (r=8, ~40M trainable parameters)
- Dataset: 300 Axinova code examples (Go + Vue)
- Training: 3 epochs, batch size 1, lr 3e-4
- Hardware: M2 Pro GPU

## Results
| Model | Code Accuracy | ROUGE-L | Human Score |
|-------|---------------|---------|-------------|
| Baseline Llama 3 | 45% | 0.32 | 2.5/5 |
| Fine-tuned Llama 3 | 78% | 0.71 | 4.2/5 |
| Tiny Transformer | 12% | 0.08 | 1.5/5 |

## Key Insights
1. **Fine-tuning >> Training from scratch** (for small datasets)
   - Llama 3 baseline already knows Go/Vue syntax
   - Fine-tuning adapts to Axinova-specific patterns (e.g., sqlc, chi router)

2. **LoRA is efficient**
   - Only 0.5% of parameters trainable
   - Training time: 3 hours (vs. weeks for full fine-tuning)
   - Model size: 40MB (LoRA weights) vs. 16GB (full model)

3. **Tiny model struggles with complex code**
   - Good at docs/text generation
   - Fails at multi-line code (lacks syntax understanding)

## Next Steps
- Increase LoRA rank (r=8 → r=16) for more capacity
- Full fine-tuning (if time/resources allow)
- Add more training examples (500-1000 samples)
- Try QLoRA (quantized LoRA) for even less memory
```

---

## Phase 3: Advanced Experiments (Ongoing)

### Experiment Ideas

1. **Retrieval-Augmented Generation (RAG)**
   - Index Axinova codebase with vector database (Chroma)
   - Retrieve relevant code before generating
   - Compare RAG vs. fine-tuning

2. **Multi-Task Fine-Tuning**
   - Train on multiple tasks: code generation, bug fixing, documentation
   - Evaluate task-specific performance

3. **Continuous Fine-Tuning**
   - Automatically fine-tune on new code commits
   - Track model drift over time

4. **Agent-Specific Models**
   - Fine-tune separate models for Backend Engineer, Frontend Engineer, etc.
   - Compare specialist vs. generalist models

5. **Quantization & Deployment**
   - Quantize models to 4-bit (GPTQ, GGUF)
   - Deploy to Ollama for fast inference
   - Benchmark latency vs. accuracy

---

## Learning Resources

**Books:**
- "Speech and Language Processing" by Jurafsky & Martin (NLP fundamentals)
- "Deep Learning" by Goodfellow et al. (transformer architecture)

**Papers:**
- "Attention Is All You Need" (Vaswani et al., 2017) - Original transformer
- "LoRA: Low-Rank Adaptation of Large Language Models" (Hu et al., 2021)
- "Llama 3 Technical Report" (Meta, 2024)

**Courses:**
- Andrej Karpathy's "Neural Networks: Zero to Hero" (YouTube)
- Stanford CS224N: Natural Language Processing
- Hugging Face NLP Course (free, online)

**Tools:**
- PyTorch: Model implementation
- Hugging Face Transformers: Pre-trained models
- PEFT: LoRA and other parameter-efficient fine-tuning
- Weights & Biases: Experiment tracking

---

## Success Metrics

**Technical Metrics:**
- Perplexity on held-out test set
- Code compilation rate (% of generated code that compiles)
- ROUGE/BLEU scores for code generation
- Training time and cost (GPU hours)

**Practical Metrics:**
- Agent code acceptance rate (% of PRs merged without changes)
- Developer satisfaction (5-point scale survey)
- Time saved (vs. manual coding)

**Learning Metrics:**
- Experiments completed per month
- Wiki pages documenting findings
- Knowledge shared with team (tutorials, presentations)

---

## Budget & Timeline

**Hardware:**
- M2 Pro Mac mini: Already owned
- Storage: 200GB (~$20 for external SSD if needed)

**Software:**
- PyTorch, Transformers: Free
- Anthropic API (for agents): ~$50/month
- Total: ~$50-70/month

**Timeline:**
- Phase 1 (Character-level transformer): 2-4 weeks
- Phase 2 (Llama 3 fine-tuning): 3-4 weeks
- Phase 3 (Advanced experiments): Ongoing (1-2 experiments/month)

**Total:** 3-6 months to complete Phases 1-2, then continuous learning

---

## Deliverables

**By End of Phase 1:**
- [ ] Trained character-level transformer checkpoint
- [ ] Corpus collection and tokenization pipeline
- [ ] Evaluation scripts (perplexity, generation)
- [ ] Wiki documentation with samples and insights

**By End of Phase 2:**
- [ ] Fine-tuned Llama 3 8B LoRA weights
- [ ] Code generation evaluation benchmark
- [ ] Comparison report (baseline vs. fine-tuned vs. tiny)
- [ ] Reusable fine-tuning pipeline

**By Month 6:**
- [ ] 5+ documented experiments
- [ ] Deployed model for agent use (code generation)
- [ ] Tutorial for future experiments
- [ ] Research paper or blog post (optional)

---

This LLM learning journey transforms the M2 Pro Mac mini into a research lab, enabling hands-on experience with modern LLM techniques while building practical tools for the agent fleet.
