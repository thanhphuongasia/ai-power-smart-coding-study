# Code cards: ReAct agent walkthrough (V1 and V2)

## Section 1: V1 cards (prompt-driven ReAct)

Each card quotes a short excerpt from apssouza22/ai-agent-react-llm (branch version-2), explains what it does, and flags the hard part. Cards are independent, so each can become one lesson card.

V1 makes one LLM call per ReAct step, and every call gets the whole history pasted into its prompt. Read the cards in order: types, memory, then the loop.

#### Card V1-1: Tool and Agent

Source: [`src/common.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/common.py)

```python
class Tool:
    def __init__(self, name: str, func, desc) -> None:
        self.desc = desc
        self.name = name
        self.func = func

class Agent(BaseModel):
    name: str = "Agent"
    model: str = "gpt-4o"
    instructions: Union[str, Callable[[], str]] = "You are a helpful agent."
    functions: List = []
    parallel_tool_calls: bool = True
    tool_choice: str = None
```

**What it does.** A `Tool` is a function plus a name and a one-line description that gets pasted into prompts. An `Agent` is plain data: a model, a system prompt and a list of tools.

**Hard part.** `Tool.func` has no type, and that is deliberate: it can be a normal function or another `Agent`. The executor checks which one it got (Card V1-8), and that check is the whole V1 handoff mechanism. Also, `Agent.functions` is an untyped list; V1 expects `Tool` objects in it, while V2 expects plain functions.

#### Card V1-2: Structured outputs for decisions

Source: [`src/common.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/common.py)

```python
class ToolChoice(BaseModel):
    tool_name: str = Field(..., description="Name of the tool to use")
    reason_of_choice: str = Field(..., description="Reason for choosing the tool")

class ReactEnd(BaseModel):
    stop: bool = Field(..., description="True if the context is enough to answer the request else False")
    final_answer: str = Field(..., description="Final answer if the context is enough to answer the request")
    confidence: float = Field(..., description="Confidence score of the final answer")
```

**What it does.** These two pydantic classes are the shapes of the model's decisions: which tool to use, and whether it can stop. The model must fill exactly these fields.

**Hard part.** The `description` texts are not comments: they are sent to the model as part of the response schema, so rewording them changes behaviour. And `final_answer` is filled even when `stop` is false, in which case it holds the model's observation, not an answer.

#### Card V1-3: AgentConfig and the broken chain

Source: [`src/common.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/common.py)

```python
class AgentConfig:
    def __init__(self):
        self.max_interactions = 3
        self.model = None
        self.token_limit: int = 5000

    def with_token_limit(self, token_limit: int):
        self.token_limit = token_limit
        return self

    def with_max_interactions(self, max_int: int):
        self.max_interactions = max_int
```

**What it does.** It holds the run settings and uses a builder style: each `with_*` method sets a value and returns `self`, so calls can be chained.

**Hard part.** `with_max_interactions` forgets `return self`, so `config.with_max_interactions(5).with_token_limit(100)` would fail because the first call returns `None`. The demo avoids the bug by calling each method as a separate statement. Also note `model` holds the OpenAI client, not a model name.

#### Card V1-4: Memory is a list of strings

Source: [`src/version1/brain.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/brain.py)

```python
class Brain:
    def __init__(self, config: AgentConfig):
        self.config = config
        self.messages = []

    def remember(self, message: str):
        self.messages.append(message)

    def recall(self) -> str:
        return "\n".join(self.messages)
```

**What it does.** The agent's whole memory is a list of text lines. `remember` appends one line; `recall` joins them into one block that later prompts paste in.

**Hard part.** Nothing is ever dropped, and `recall()` is pasted into every one of the three or four prompts of every iteration. Prompt size therefore grows with each step, which is why `AgentConfig` has a token limit and why long tasks get expensive. There is no summarising or trimming.

#### Card V1-5: Brain.think, the only LLM call

Source: [`src/version1/brain.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/brain.py)

```python
        openai_params = {
            "model": agent.model,
            "temperature": 0.1,
            "max_tokens": self.config.token_limit,
            "messages": messages
        }
        if output_format:
            openai_params["response_format"] = output_format
            completion = self.config.model.beta.chat.completions.parse(**openai_params)
            return completion.choices[0].message.parsed

        completion = self.config.model.chat.completions.create(**openai_params)
        return completion.choices[0].message.content
```

**What it does.** `think` is the single place that talks to the model. Without `output_format` it returns plain text; with a pydantic class it asks the API to parse the reply into that class and returns the object.

**Hard part.** `messages` has three entries: a fixed system message, the agent's own `instructions` as a second system message, and the step prompt as the user message. So the agent's personality is applied to every step. And `self.config.model` is the OpenAI client (a confusing name): the `.beta...parse` call is the structured-output endpoint.

#### Card V1-6: The ReAct loop

Source: [`src/version1/reactexecutor.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/reactexecutor.py)

```python
        while True:
            total_interactions += 1
            if self.config.max_interactions <= total_interactions:
                print("Max interactions reached. Exiting.")
                return ""

            print("Current Agent: ", agent.name)
            self.__thought(agent)
            agent, skip = self.__action(agent)
            if skip:
                continue
            observation = self.__observation(agent)
            if observation.stop:
                print("Thought: I now know the final answer. \n")
                print(f"Final Answer: {observation.final_answer}")
                return observation.final_answer
```

**What it does.** This is ReAct in twelve lines: think, act, observe, and repeat until the observation says stop.

**Hard part.** Three details are easy to miss. First, `skip` is true when the action was an agent switch or an unknown tool; the loop then jumps back to Thought without an Observation. Second, the guard uses `<=`, so `max_interactions=10` allows only 9 iterations. Third, hitting the cap returns an empty string, so a caller cannot tell a cut-off run from an empty answer.

#### Card V1-7: The Thought step is a prompt, not a feature

Source: [`src/version1/reactexecutor.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/reactexecutor.py)

```python
        prompt = f"""Answer the following request as best you can: {self.request}.

First think step by step about what to do. Plan step by step what to do.
...
Your available tools are:
{tools}

CONTEXT HISTORY:
---
{self.brain.recall()}
"""
        response = self.brain.think(prompt=prompt, agent=current_agent)
        self.brain.remember("Assistant: " + response)
```

(The `...` marks lines left out here.)

**What it does.** It builds a prompt from the request, the tool list and the memory so far, asks for a plan, and stores the plan as a new memory line.

**Hard part.** There is no built-in "reasoning mode". The Thought is just text produced because the prompt asks for step-by-step planning. The model sees its earlier thoughts only because `recall()` pastes them under `CONTEXT HISTORY`, as plain text rather than as chat messages.

#### Card V1-8: Choosing a tool, and the V1 handoff

Source: [`src/version1/reactexecutor.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/reactexecutor.py)

```python
    def __action(self, agent: Agent) -> tuple[Agent, bool]:
        tool = self.__choose_action(agent)
        if tool:
            if isinstance(tool.func, Agent):
                agent = tool.func
                print(f"Switching to the Agent: {agent.name} \n")
                return agent, True

            self.__execute_action(tool, agent)
        else:
            print("No tool found")
            agent = self.base_agent
            return agent, True
        return agent, False
```

**What it does.** `__choose_action` asks the model for a `ToolChoice` and looks the name up in `agent.functions`. Then there are three outcomes: the tool wraps an Agent (switch to it), the tool is a normal function (run it), or no tool matches (fall back to the base agent).

**Hard part.** A handoff is just reassigning the local variable `agent`, and returning `True` skips the Observation. The sub-agent stays active on later iterations. The sample code has no explicit "return" tool: control goes back to the base agent only when the model names a tool that does not exist in the active agent's list.

#### Card V1-9: Asking the model for tool arguments

Source: [`src/version1/reactexecutor.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/reactexecutor.py)

```python
        parameters = inspect.signature(tool.func).parameters
        response = {}
        if len(parameters) > 0:
            prompt += f"""RESPONSE FORMAT:
            {{
                {', '.join([f'"{param}": <function parameter>' for param in parameters])}
            }}"""
            response = self.brain.think(prompt=prompt, agent=agent)
            ...
            try:
                response = json.loads(response)
            except Exception as e:
                ...
                return

        action_result = tool.func(**response)
```

**What it does.** It reads the parameter names from the function signature, asks the model to reply with a JSON object using those names, parses it, and calls the function with the result.

**Hard part.** The doubled braces `{{` and `}}` are f-string escapes that print a single brace. The model must return bare JSON: if it wraps the answer in a markdown fence, `json.loads` fails, the error is stored in memory, and the iteration ends without running the tool. A tool with no parameters costs no extra LLM call.

#### Card V1-10: Observation and the unused confidence score

Source: [`src/version1/reactexecutor.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/reactexecutor.py)

```python
Assign a quality confidence score between 0.0 and 1.0 to guide your approach:
   - 0.8+: Continue current approach
   - 0.5-0.7: Consider minor adjustments
   - Below 0.5: Seriously consider backtracking and trying a different approach
...
        response: ReactEnd = self.brain.think(prompt=prompt, agent=current_agent, output_format=ReactEnd)
        self.brain.remember("Assistant: " + response.final_answer)
        self.brain.remember("Assistant: " + f"Confidence score: {response.confidence}")
```

**What it does.** The Observation step asks whether the memory now contains enough to answer, as a `ReactEnd` object. Its text and its confidence score are both stored in memory.

**Hard part.** The first four lines are prompt text, the rest is code. The confidence number never drives any `if` in the code: the executor only checks `observation.stop`. The score matters only because it is written back into memory, where the next Thought can read it.

#### Card V1-11: Wiring the demo, including a sub-agent

Source: [`src/version1/tools.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version1/tools.py) and [`examples/search/main.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/examples/search/main.py)

```python
calculator_tool = Tool("Calculator", perform_calculator, "To perform math calculations")
wikipedia_tool = Tool("Wikipedia_search", search_wikipedia, "To search for information on wikipedia")
today_tool = Tool("Date_of_today", date_of_today, "To get the date of today")
people_search_tool = Tool("People_search", people_search_agent, "To search for person information")
people_search_agent.functions = [wikipedia_tool]
```

```python
agent_config = AgentConfig()
agent_config.with_model_client(open_ai)
agent_config.with_token_limit(5000)
agent_config.with_max_interactions(10)
react_exec = ReActExecutor(agent_config, main_agent)
react_exec.execute(query)
```

**What it does.** Four tools are created; `People_search` wraps a whole agent instead of a function. The main agent gets Calculator, Date_of_today and People_search, and the sub-agent gets only Wikipedia_search. Then the config is set up and the executor runs a query.

**Hard part.** The sub-agent's tool list is assigned on the last line of `tools.py`, after `people_search_tool` already points at it. The agent object is created near the top of the file, before `wikipedia_tool` exists, so its tool list can only be filled in at the end. This works because `people_search_tool` holds a reference to the same Agent object, so the late assignment is visible through it.

## Section 2: V2 cards (function calling and handoff)

V2 lets the model choose tools through the API's native tool calls. The code only builds requests, runs the requested functions and decides which agent speaks next. Cards 1 to 3 are the building blocks, 4 to 7 are the engine, 8 to 11 are the airline demo.

#### Card V2-1: Turning a Python function into a tool schema

Source: [`src/version2/utils.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version2/utils.py)

```python
    parameters = {}
    for param in signature.parameters.values():
        ...
        param_type = type_map.get(param.annotation, "string")
        parameters[param.name] = {"type": param_type}

    required = [
        param.name
        for param in signature.parameters.values()
        if param.default == inspect._empty
    ]

    return {
        "type": "function",
        "function": {
            "name": func.__name__,
            "description": func.__doc__ or "",
            "parameters": {
                "type": "object",
                "properties": parameters,
                "required": required,
            },
        },
    }
```

**What it does.** It reads a function's signature with `inspect` and builds the JSON the API expects: the function name, its docstring as the description, one property per parameter, and the list of required parameters.

**Hard part.** A parameter is required when it has no default value (`inspect._empty` is the marker for "no default"). Types come from a small lookup table (`str`, `int`, `float`, `bool`, `list`, `dict`); anything else, including a missing annotation or `Optional[str]`, silently becomes `"string"`. The airline tools have no docstrings, so the model chooses them by name alone.

#### Card V2-2: Agent builds its own request pieces

Source: [`src/common.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/common.py)

```python
    def tools_in_json(self):
        return [function_to_json(f) for f in self.functions]

    def get_instructions(self, context_variables: dict = {}) -> str:
        if callable(self.instructions):
            return self.instructions(context_variables)
        return self.instructions
```

**What it does.** `tools_in_json` converts every tool of the agent into a schema. `get_instructions` returns the system prompt: a fixed string as is, or the result of calling a function that receives the context variables.

**Hard part.** `instructions` can be either a string or a function, which is how one prompt can embed per-customer data (Card V2-9). The `callable` check is the only thing that distinguishes the two. The default argument `{}` is a shared mutable object, a classic Python trap; it is harmless here only because the code never changes it.

#### Card V2-3: Two result types with different jobs

Source: [`src/version2/types.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version2/types.py)

```python
class TaskResponse(BaseModel):
    messages: List = []
    agent: Optional[Agent] = None
    context_variables: dict = {}

class FuncResult(BaseModel):
    value: str = ""
    agent: Optional[Agent] = None
    context_variables: dict = {}
```

**What it does.** `FuncResult` is what one tool call produced: some text and, optionally, the next agent. `TaskResponse` is what a whole run, or one batch of tool calls, produced: new messages and, optionally, the agent that should speak next.

**Hard part.** The two classes look almost identical, so keep the scopes apart: one tool, versus one run. Both carry `context_variables`, but nothing copies a tool's variables back into the run, so a tool cannot update shared state today. That is a gap you can fix as an exercise.

#### Card V2-4: Building one request

Source: [`src/version2/runner.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version2/runner.py)

```python
        context_variables = defaultdict(str, variables)
        instructions = agent.get_instructions(context_variables)
        messages = [{"role": "system", "content": instructions}] + history
        tools = agent.tools_in_json()
        ...
        params = {
            "model": agent.model,
            "messages": messages,
            "tool_choice": agent.tool_choice
        }
        if tools:
            params["parallel_tool_calls"] = agent.parallel_tool_calls
            params["tools"] = tools

        return params
```

**What it does.** It resolves the active agent's prompt, puts it first, appends the conversation history, and adds the agent's tool schemas when it has any.

**Hard part.** The system message is rebuilt on every call and is never stored in `history`. That is exactly what makes handoff cheap: change the active agent and the next request carries a new prompt and new tools over the same history. `defaultdict(str, ...)` makes a missing context key read as an empty string instead of raising an error. `parallel_tool_calls` is added only together with `tools`, because the API only accepts that option alongside tools.

#### Card V2-5: The agent loop

Source: [`src/version2/runner.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version2/runner.py)

```python
        while loop_count < max_interactions:
            ...
            response = self.client.chat.completions.create(**llm_params)
            message: ChatCompletionMessage = response.choices[0].message
            ...
            message.sender = active_agent.name
            history_msg = json.loads(message.model_dump_json())
            history.append(history_msg)
            loop_count += 1
            if not message.tool_calls:
                break
            ...
            response =self.tool_handler.handle_tool_calls(
                message.tool_calls,
                active_agent.functions,
            )
            history.extend(response.messages)
            if response.agent:
                active_agent = response.agent

        return TaskResponse(
            messages=history[init_len:],
            agent=active_agent,
            context_variables=context_variables
        )
```

**What it does.** Call the model, record its reply, and stop if it asked for no tools. Otherwise run the tools, record their results, switch agent if one was returned, and go round again.

**Hard part.** Order matters: the assistant message with `tool_calls` must be in history before the matching `tool` messages, or the next API call is rejected. `history[init_len:]` returns only messages created during this run, so the caller appends them to its own list. If the loop ends because of the cap, it just falls out of the `while` and returns normally, with no signal that the run was cut off. And `sender` is an extra key added to the message, which then travels back to the API on every later call.

#### Card V2-6: Normalising what a tool returns

Source: [`src/version2/result_handler.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version2/result_handler.py)

```python
        if isinstance(result, FuncResult):
            return result

        if isinstance(result, Agent):
            agent: Agent = result
            return FuncResult(
                value=json.dumps({"assistant": agent.name}),
                agent=agent,
            )

        try:
            return FuncResult(value=str(result))
```

**What it does.** A tool function may return a `FuncResult`, an `Agent` or anything else. This method turns all three into a `FuncResult`.

**Hard part.** The Agent branch does two things at once: it keeps the agent object so the runner can switch to it, and it writes `{"assistant": "<name>"}` as the tool message text, so the model can read who it handed over to. The `try` around the `str(...)` fallback only matters for objects that cannot be converted to text.

#### Card V2-7: Running one tool call

Source: [`src/version2/result_handler.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/src/version2/result_handler.py)

```python
        name = tool_call.function.name
        if name not in function_map:
            ...
            partial_response.messages.append({
                "role": "tool",
                "tool_name": name,
                "tool_call_id": tool_call.id,
                "content": f"Error: tool {name} not found"
            })
            return
        raw_result = self.__execute_tool(function_map, name, tool_call)

        ...
        args = json.loads(tool_call.function.arguments)
        return function_map[name](**args)
```

**What it does.** It looks the requested name up in a map built from the agent's functions. An unknown name produces an error message for the model; a known name is run with the model's arguments as keyword arguments.

**Hard part.** Every tool call must be answered by exactly one `tool` message carrying the same `tool_call_id`, even when the answer is an error, otherwise the API refuses the next request. The arguments arrive as a JSON string and go straight into `function(**args)`: a tool that raises, or arguments that are not valid JSON, will crash the whole run, because nothing catches the error. When several calls in one batch return agents, the last one wins.

#### Card V2-8: A handoff is a function that returns an Agent

Source: [`examples/airline/agents.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/examples/airline/agents.py)

```python
def transfer_to_lost_baggage():
    return lost_baggage_agent

def transfer_to_triage():
    return triage_agent

...
triage_agent = Agent(
    name="Triage Agent",
    instructions=triage_instructions,
    functions=[transfer_to_lost_baggage, transfer_to_flight_modification],
)
```

**What it does.** The transfer functions do nothing except return an agent object. Because the handler turns a returned Agent into a switch (Card V2-6), listing such a function in `functions` gives the model a way to hand over.

**Hard part.** `transfer_to_lost_baggage` refers to `lost_baggage_agent`, which is defined further down, while `transfer_to_triage` refers to `triage_agent`, which is defined at the bottom of the file. That works because Python looks up the name when the function is called, not when it is written. The same trick lets triage and the specialists point at each other without a circular import.

#### Card V2-9: A prompt that reads the customer context

Source: [`examples/airline/agents.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/examples/airline/agents.py)

```python
def triage_instructions(context_variables):
    customer_context = context_variables.get("customer_context", None)
    flight_context = context_variables.get("flight_context", None)
    return f"""You are to triage a users request, and call a tool to transfer to the right intent.
    ...
    The customer context is here: {customer_context}, and flight context is here: {flight_context}"""
```

**What it does.** The triage prompt is a function. On every call the runner passes the context variables, and the function pastes the customer and flight details into the system prompt.

**Hard part.** Only the triage agent has this kind of dynamic prompt. The specialists use fixed strings (`STARTER_PROMPT` plus a policy), so they never see the customer or flight context, even though their starter prompt tells the model that context is available. If a specialist needs the data, its instructions must also become a function.

#### Card V2-10: A policy prompt acts as a state machine

Source: [`examples/airline/flight_modification.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/examples/airline/flight_modification.py)

```python
1. Confirm which flight the customer is asking to cancel.
1a) If the customer is asking about the same flight, proceed to next step.
1b) If the customer is not, call 'escalate_to_human' function.
2. Confirm if the customer wants a refund or flight credits.
3. If the customer wants a refund follow step 3a). If the customer wants flight credits move to step 4.
3a) Call the initiate_refund function.
```

**What it does.** The cancel agent's instructions are a numbered procedure with branches. Each branch names the exact function to call, so the conversation walks through the steps.

**Hard part.** The control flow lives only in the prompt, so nothing in Python forces the order: the model follows it by obedience. The function names inside the prompt must match the tool names exactly, otherwise the model asks for a tool that does not exist (Card V2-7 then returns the error message). The same prompt style is used for baggage and flight change.

#### Card V2-11: The console loop keeps the active agent

Source: [`examples/airline/airline-app.py`](https://github.com/apssouza22/ai-agent-react-llm/blob/version-2/examples/airline/airline-app.py)

```python
    runner = AppRunner(client = OpenAI())
    messages = []
    agent = triage_agent
    while True:
        query = input("Enter your query: ")
        messages.append({"role": "user", "content": query})
        response = runner.run(agent, messages, context_variables)
        messages.extend(response.messages)
        agent = response.agent
        pretty_print_messages(response.messages)
```

**What it does.** It reads a line, runs the agent, appends the new messages to its own history, and remembers which agent finished the turn.

**Hard part.** Two lines carry the state between turns: `messages.extend(response.messages)` (the runner returns only new messages, so the caller must keep the full list) and `agent = response.agent` (without it, every new turn would start again at triage). The loop has no exit and no limit on history size.

## Licence note

The excerpts above come from [apssouza22/ai-agent-react-llm](https://github.com/apssouza22/ai-agent-react-llm/tree/version-2), which is published under the MIT License (Copyright (c) 2023 Shunyu Yao). Keep that notice when you reuse the code in a lesson.
