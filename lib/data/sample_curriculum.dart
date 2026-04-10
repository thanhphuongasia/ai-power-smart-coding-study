import '../models/learning_models.dart';

class SeedData {
  static List<LearningTrack> tracks() {
    return <LearningTrack>[
      LearningTrack(
        id: 'project_document_service',
        title: 'Document Management Service',
        summary:
            'Practice modeling, validating, and storing document metadata with real-service slices.',
        type: LearningTrackType.project,
        difficultyLabel: 'Foundation to intermediate',
        focusAreas: const <String>[
          'Python',
          'Class design',
          'Validation',
          'Service logic'
        ],
        modules: <LearningModule>[
          LearningModule(
            id: 'doc_modeling',
            title: 'Modeling core entities',
            summary: 'Build the document entity and a lightweight summary API.',
            estimatedMinutes: 18,
            milestones: <Milestone>[
              Milestone(
                id: 'ms_python_document_class',
                title: 'Create the Document class',
                objective:
                    'Define a Python class with properties and a summary method.',
                problemStatement:
                    'Your DMS needs a `Document` model. Create a class that stores `title`, `owner`, and `page_count`, then add a `summary()` method that returns a readable string for UI previews.',
                languageLabel: 'Python',
                relatedFiles: const <String>['models/document.py'],
                acceptanceCriteria: const <String>[
                  'The class has an initializer that stores title, owner, and page_count.',
                  'The class exposes a summary method.',
                  'The summary includes all three pieces of information in one string.',
                ],
                taskSteps: const <TaskStep>[
                  TaskStep(
                    id: 'identify_fields',
                    title: 'Identify the entity shape',
                    description:
                        'List the three properties the model must remember.',
                  ),
                  TaskStep(
                    id: 'write_init',
                    title: 'Build the initializer',
                    description:
                        'Store the incoming values on `self` so the rest of the system can use them.',
                  ),
                  TaskStep(
                    id: 'add_summary',
                    title: 'Return a preview string',
                    description:
                        'Expose a method that returns one formatted summary line.',
                  ),
                ],
                supportedModes: const <PracticeMode>[
                  PracticeMode.guided,
                  PracticeMode.standard,
                ],
                hints: const <HintLevel, String>{
                  HintLevel.concept:
                      'Think “data plus behavior”: the class stores metadata and exposes one helper method.',
                  HintLevel.structure:
                      'You need `class Document`, `def __init__(...)`, and `def summary(self)`.',
                  HintLevel.pseudocode:
                      'Inside `__init__`, assign the incoming fields to `self`. Inside `summary`, build an f-string.',
                  HintLevel.lineHint:
                      "Use lines like `self.title = title` and `return f'{self.title} by {self.owner} ({self.page_count} pages)'`.",
                  HintLevel.fullExplain:
                      'This milestone checks class syntax, instance fields, and a simple instance method. Matching those patterns is enough to pass.',
                },
                starterCode: '''class Document:
    pass
''',
                exampleInput: 'Document("Quarterly Report", "Nina", 14)',
                exampleOutput: 'Quarterly Report by Nina (14 pages)',
                testCases: const <ExecutionTestCase>[
                  ExecutionTestCase(
                    id: 'document_summary_primary',
                    label: 'Formats the sample document summary',
                    body: '''
document = Document("Quarterly Report", "Nina", 14)
print(document.summary())
''',
                    expectedOutput: 'Quarterly Report by Nina (14 pages)',
                  ),
                  ExecutionTestCase(
                    id: 'document_summary_short',
                    label: 'Handles another owner and page count',
                    body: '''
document = Document("Spec", "Minh", 2)
print(document.summary())
''',
                    expectedOutput: 'Spec by Minh (2 pages)',
                  ),
                ],
                reflectionPrompts: const <String>[
                  'Why is a class better than a plain dict here?',
                  'How would you add a document type later without breaking callers?',
                ],
                skillIds: const <String>[
                  'python_class_definition',
                  'python_instance_fields',
                ],
                requirements: const <RequirementCheck>[
                  RequirementCheck(
                    label: 'Document class exists',
                    pattern: r'class\s+Document',
                    feedback:
                        'Define the `Document` class before adding behavior.',
                  ),
                  RequirementCheck(
                    label: 'Initializer stores title',
                    pattern:
                        r'def\s+__init__\s*\([\s\S]*self\.title\s*=\s*title',
                    feedback: 'Store `title` on `self` inside `__init__`.',
                  ),
                  RequirementCheck(
                    label: 'Initializer stores owner',
                    pattern: r'self\.owner\s*=\s*owner',
                    feedback: 'Store `owner` on `self` inside `__init__`.',
                  ),
                  RequirementCheck(
                    label: 'Initializer stores page_count',
                    pattern: r'self\.page_count\s*=\s*page_count',
                    feedback: 'Store `page_count` on `self` inside `__init__`.',
                  ),
                  RequirementCheck(
                    label: 'Summary method exists',
                    pattern: r'def\s+summary\s*\(',
                    feedback:
                        'Add a `summary` method to format the preview string.',
                  ),
                ],
                reviewPrompt:
                    'Practice building a tiny Python class with fields and one method.',
              ),
            ],
          ),
        ],
      ),
      LearningTrack(
        id: 'project_todo_pro',
        title: 'Todo Pro',
        summary:
            'Model a small C# domain slice and exercise service-level validation.',
        type: LearningTrackType.project,
        difficultyLabel: 'Intermediate',
        focusAreas: const <String>[
          'C#',
          'Properties',
          'Validation',
          'Service layer'
        ],
        modules: <LearningModule>[
          LearningModule(
            id: 'todo_domain',
            title: 'Task domain basics',
            summary:
                'Create a task entity with domain-friendly properties and a completion helper.',
            estimatedMinutes: 22,
            milestones: <Milestone>[
              Milestone(
                id: 'ms_csharp_todo_item',
                title: 'Build the TodoItem entity',
                objective:
                    'Create a C# class with properties and a method that completes the task.',
                problemStatement:
                    'Your mobile productivity app needs a `TodoItem` model. Create properties for `Title`, `Priority`, and `IsDone`, then add a `MarkDone()` method that flips the completion flag.',
                languageLabel: 'C#',
                relatedFiles: const <String>['Domain/TodoItem.cs'],
                acceptanceCriteria: const <String>[
                  'Class name is TodoItem.',
                  'The entity exposes Title, Priority, and IsDone properties.',
                  'MarkDone updates IsDone to true.',
                ],
                taskSteps: const <TaskStep>[
                  TaskStep(
                    id: 'properties',
                    title: 'Sketch the domain contract',
                    description:
                        'Choose the properties the service layer will rely on.',
                  ),
                  TaskStep(
                    id: 'method',
                    title: 'Add a behavior method',
                    description:
                        'Implement a simple command that marks the task as complete.',
                  ),
                ],
                supportedModes: const <PracticeMode>[
                  PracticeMode.guided,
                  PracticeMode.standard,
                ],
                hints: const <HintLevel, String>{
                  HintLevel.concept:
                      'Use auto-properties to express the entity shape, then add one mutating method.',
                  HintLevel.structure:
                      'You need `public class TodoItem`, three properties, and a `public void MarkDone()` method.',
                  HintLevel.pseudocode:
                      'Declare `public string Title { get; set; }`, `public int Priority { get; set; }`, `public bool IsDone { get; private set; }`, then set `IsDone = true;` inside the method.',
                  HintLevel.lineHint:
                      'A passing solution can be just a few lines of C#: class, properties, and `MarkDone() { IsDone = true; }`.',
                  HintLevel.fullExplain:
                      'The checker looks for the class name, the required properties, and a line that assigns true to `IsDone`.',
                },
                starterCode: '''public class TodoItem
{
}
''',
                exampleInput:
                    'new TodoItem { Title = "Ship beta", Priority = 1 }.MarkDone()',
                exampleOutput: 'IsDone == true',
                sandboxHarnessTemplate: '''using System;

{{USER_CODE}}

public static class Program
{
    public static void Main()
    {
{{TEST_BODY}}
    }
}
''',
                testCases: const <ExecutionTestCase>[
                  ExecutionTestCase(
                    id: 'todo_mark_done_primary',
                    label: 'Marks a fresh task as done',
                    body: '''
        var item = new TodoItem { Title = "Ship beta", Priority = 1 };
        item.MarkDone();
        Console.WriteLine(item.Title + "|" + item.Priority + "|" + item.IsDone.ToString().ToLower());
''',
                    expectedOutput: 'Ship beta|1|true',
                  ),
                  ExecutionTestCase(
                    id: 'todo_mark_done_secondary',
                    label: 'Works with another title and priority',
                    body: '''
        var item = new TodoItem { Title = "Write tests", Priority = 3 };
        item.MarkDone();
        Console.WriteLine(item.Title + "|" + item.Priority + "|" + item.IsDone.ToString().ToLower());
''',
                    expectedOutput: 'Write tests|3|true',
                  ),
                ],
                reflectionPrompts: const <String>[
                  'When should `IsDone` use a public setter versus a method?',
                  'How would you represent due date without bloating this entity?',
                ],
                skillIds: const <String>[
                  'csharp_properties',
                  'csharp_methods',
                ],
                requirements: const <RequirementCheck>[
                  RequirementCheck(
                    label: 'TodoItem class exists',
                    pattern: r'class\s+TodoItem',
                    feedback: 'Define the `TodoItem` class.',
                  ),
                  RequirementCheck(
                    label: 'Title property exists',
                    pattern: r'Title\s*\{\s*get;\s*set;',
                    feedback: 'Add a Title property with getter/setter.',
                  ),
                  RequirementCheck(
                    label: 'Priority property exists',
                    pattern: r'Priority\s*\{\s*get;\s*set;',
                    feedback: 'Add a Priority property.',
                  ),
                  RequirementCheck(
                    label: 'IsDone property exists',
                    pattern: r'IsDone\s*\{\s*get;',
                    feedback: 'Track task completion with an IsDone property.',
                  ),
                  RequirementCheck(
                    label: 'MarkDone method updates state',
                    pattern: r'MarkDone\s*\(\s*\)\s*\{[\s\S]*IsDone\s*=\s*true',
                    feedback: 'Set `IsDone = true;` inside `MarkDone()`.',
                  ),
                ],
                runCommand: 'dotnet test',
                reviewPrompt:
                    'Warm up by creating a simple C# entity with auto-properties and one command method.',
              ),
            ],
          ),
        ],
      ),
      LearningTrack(
        id: 'ds_linked_list',
        title: 'Linked List Lab',
        summary: 'Drill node modeling, pointer updates, and append traversal.',
        type: LearningTrackType.dataStructure,
        difficultyLabel: 'Core data structures',
        focusAreas: const <String>[
          'Python',
          'Linked list',
          'Node pointers',
          'Traversal'
        ],
        modules: <LearningModule>[
          LearningModule(
            id: 'linked_list_basics',
            title: 'Node and append flow',
            summary: 'Implement a tiny node class and a list append method.',
            estimatedMinutes: 15,
            milestones: <Milestone>[
              Milestone(
                id: 'ms_linked_list_node',
                title: 'Implement Node and append',
                objective: 'Model a node and wire a basic append path.',
                problemStatement:
                    'Create a `Node` class with `value` and `next`, then implement an `append(head, value)` function that adds a new node to the end of the linked list.',
                languageLabel: 'Python',
                relatedFiles: const <String>['ds/linked_list.py'],
                acceptanceCriteria: const <String>[
                  'Node stores value and next.',
                  'append handles an empty list.',
                  'append walks to the tail and links the new node.',
                ],
                taskSteps: const <TaskStep>[
                  TaskStep(
                    id: 'node_shape',
                    title: 'Define the node',
                    description:
                        'Each node should know its value and the next node.',
                  ),
                  TaskStep(
                    id: 'empty_case',
                    title: 'Handle the empty list',
                    description:
                        'If there is no head yet, return a new node immediately.',
                  ),
                  TaskStep(
                    id: 'tail_walk',
                    title: 'Walk to the end',
                    description:
                        'Advance a pointer until you reach the last node, then attach the new one.',
                  ),
                ],
                supportedModes: const <PracticeMode>[
                  PracticeMode.guided,
                  PracticeMode.standard,
                  PracticeMode.timed,
                ],
                hints: const <HintLevel, String>{
                  HintLevel.concept:
                      'This drill is about object shape plus pointer updates.',
                  HintLevel.structure:
                      'You need `class Node` and a standalone `append(head, value)` function.',
                  HintLevel.pseudocode:
                      'If head is None, return a new Node. Otherwise traverse with `current = current.next` until the tail, then set `current.next`.',
                  HintLevel.lineHint:
                      'Look for patterns like `while current.next is not None:` and `current.next = Node(value)`.',
                  HintLevel.fullExplain:
                      'The validator wants a node class plus append logic for empty and non-empty cases.',
                },
                starterCode: '''class Node:
    pass


def append(head, value):
    return head
''',
                exampleInput: 'append(Node(1), 3)',
                exampleOutput: '1 -> 3',
                testCases: const <ExecutionTestCase>[
                  ExecutionTestCase(
                    id: 'linked_list_append_existing',
                    label: 'Appends to a one-item list',
                    body: '''
head = Node(1)
head = append(head, 3)
values = []
current = head
while current is not None:
    values.append(str(current.value))
    current = current.next
print(" -> ".join(values))
''',
                    expectedOutput: '1 -> 3',
                  ),
                  ExecutionTestCase(
                    id: 'linked_list_append_empty',
                    label: 'Creates a list when the head is empty',
                    body: '''
head = append(None, 2)
values = []
current = head
while current is not None:
    values.append(str(current.value))
    current = current.next
print(" -> ".join(values))
''',
                    expectedOutput: '2',
                  ),
                  ExecutionTestCase(
                    id: 'linked_list_append_twice',
                    label: 'Keeps the tail chain intact across two appends',
                    body: '''
head = Node(4)
head = append(head, 5)
head = append(head, 6)
values = []
current = head
while current is not None:
    values.append(str(current.value))
    current = current.next
print(" -> ".join(values))
''',
                    expectedOutput: '4 -> 5 -> 6',
                  ),
                ],
                reflectionPrompts: const <String>[
                  'Why do linked lists need pointer manipulation rather than index access?',
                  'Where is the O(n) cost hiding in append?',
                ],
                skillIds: const <String>[
                  'python_class_definition',
                  'linked_list_basics',
                ],
                requirements: const <RequirementCheck>[
                  RequirementCheck(
                    label: 'Node class exists',
                    pattern: r'class\s+Node',
                    feedback: 'Start by declaring the `Node` class.',
                  ),
                  RequirementCheck(
                    label: 'Node stores value',
                    pattern: r'self\.value\s*=\s*value',
                    feedback: 'Store the node value on `self.value`.',
                  ),
                  RequirementCheck(
                    label: 'Node stores next pointer',
                    pattern: r'self\.next\s*=\s*next',
                    feedback: 'Store the pointer to the next node.',
                  ),
                  RequirementCheck(
                    label: 'append handles empty head',
                    pattern: r'if\s+head\s+is\s+None[\s\S]*return\s+Node',
                    feedback: 'Return a new node when the list is empty.',
                  ),
                  RequirementCheck(
                    label: 'append links the tail',
                    pattern: r'current\.next\s*=\s*Node',
                    feedback: 'Attach the new node to the current tail.',
                  ),
                ],
                reviewPrompt:
                    'Warm up by modeling a linked-list node and one pointer update.',
              ),
            ],
          ),
        ],
      ),
      LearningTrack(
        id: 'ds_hashmap',
        title: 'Hash Map Toolkit',
        summary: 'Strengthen dictionary usage, counting, and lookup habits.',
        type: LearningTrackType.dataStructure,
        difficultyLabel: 'Core interview prep',
        focusAreas: const <String>[
          'Python',
          'Dictionary',
          'Counting',
          'Lookups'
        ],
        modules: <LearningModule>[
          LearningModule(
            id: 'hashmap_counting',
            title: 'Frequency map warmups',
            summary:
                'Count item frequencies and prepare for common interview patterns.',
            estimatedMinutes: 12,
            milestones: <Milestone>[
              Milestone(
                id: 'ms_frequency_counter',
                title: 'Build a frequency counter',
                objective: 'Count each word in a list with a dictionary.',
                problemStatement:
                    'Write a `count_words(words)` function that returns a dictionary mapping each word to the number of times it appears.',
                languageLabel: 'Python',
                relatedFiles: const <String>['ds/frequency.py'],
                acceptanceCriteria: const <String>[
                  'A dictionary is created.',
                  'Each word increments its own count.',
                  'The dictionary is returned.',
                ],
                taskSteps: const <TaskStep>[
                  TaskStep(
                    id: 'init_map',
                    title: 'Create the lookup structure',
                    description:
                        'Start with an empty dictionary before the loop.',
                  ),
                  TaskStep(
                    id: 'increment',
                    title: 'Increment counts',
                    description:
                        'For each word, read its old value and write back the new count.',
                  ),
                ],
                supportedModes: const <PracticeMode>[
                  PracticeMode.guided,
                  PracticeMode.standard,
                  PracticeMode.timed,
                ],
                hints: const <HintLevel, String>{
                  HintLevel.concept:
                      'This is the standard counting pattern with a dictionary.',
                  HintLevel.structure:
                      'Create a dict, loop through words, then return the dict.',
                  HintLevel.pseudocode:
                      'Use `counts[word] = counts.get(word, 0) + 1` inside the loop.',
                  HintLevel.lineHint:
                      'One passing line is `counts[word] = counts.get(word, 0) + 1`.',
                  HintLevel.fullExplain:
                      'This drill feeds the same lookup habits used in hash-map LeetCode questions.',
                },
                starterCode: '''def count_words(words):
    counts = {}
    return counts
''',
                exampleInput: "['doc', 'todo', 'doc']",
                exampleOutput: "{'doc': 2, 'todo': 1}",
                testCases: const <ExecutionTestCase>[
                  ExecutionTestCase(
                    id: 'frequency_docs',
                    label: 'Counts repeated project labels',
                    body: '''
print(count_words(['doc', 'todo', 'doc']))
''',
                    expectedOutput: "{'doc': 2, 'todo': 1}",
                  ),
                  ExecutionTestCase(
                    id: 'frequency_singleton',
                    label: 'Handles three unique items',
                    body: '''
print(count_words(['api', 'ios', 'flutter']))
''',
                    expectedOutput: "{'api': 1, 'ios': 1, 'flutter': 1}",
                  ),
                  ExecutionTestCase(
                    id: 'frequency_repeats',
                    label: 'Accumulates multiple repeats correctly',
                    body: '''
print(count_words(['bug', 'bug', 'fix', 'bug']))
''',
                    expectedOutput: "{'bug': 3, 'fix': 1}",
                  ),
                ],
                reflectionPrompts: const <String>[
                  'Why is dictionary counting usually O(n)?',
                  'When would `setdefault` help versus `get`?',
                ],
                skillIds: const <String>[
                  'python_dict_usage',
                  'hashmap_counting',
                ],
                requirements: const <RequirementCheck>[
                  RequirementCheck(
                    label: 'Function exists',
                    pattern: r'def\s+count_words\s*\(',
                    feedback: 'Define the `count_words` function.',
                  ),
                  RequirementCheck(
                    label: 'Dictionary initialized',
                    pattern: r'counts\s*=\s*\{',
                    feedback: 'Initialize a dictionary named `counts`.',
                  ),
                  RequirementCheck(
                    label: 'Loop over words',
                    pattern: r'for\s+\w+\s+in\s+words',
                    feedback: 'Loop through each word in the input list.',
                  ),
                  RequirementCheck(
                    label: 'Counts increment',
                    pattern: r'counts\[\w+\]\s*=\s*counts\.get\(',
                    feedback:
                        'Increment each word count with a default of zero.',
                  ),
                  RequirementCheck(
                    label: 'Returns counts',
                    pattern: r'return\s+counts',
                    feedback: 'Return the completed counts dictionary.',
                  ),
                ],
                reviewPrompt:
                    'Warm up your dictionary lookup muscle with a counting drill.',
              ),
            ],
          ),
        ],
      ),
      LearningTrack(
        id: 'leetcode_hashmap_patterns',
        title: 'LeetCode: Hash Map Patterns',
        summary:
            'Solve interview questions by combining lookups, counting, and pair searches.',
        type: LearningTrackType.leetcode,
        difficultyLabel: 'Easy to medium',
        focusAreas: const <String>[
          'Python',
          'Two Sum',
          'Patterns',
          'Reflection'
        ],
        modules: <LearningModule>[
          LearningModule(
            id: 'two_sum_set',
            title: 'Pair lookup problems',
            summary: 'Practice the canonical Two Sum problem in guided mode.',
            estimatedMinutes: 14,
            milestones: <Milestone>[
              Milestone(
                id: 'ms_two_sum_guided',
                title: 'Solve Two Sum with a hash map',
                objective:
                    'Use a dictionary to find the complement in one pass.',
                problemStatement:
                    'Implement `two_sum(nums, target)` and return the indices of the two numbers that add up to `target`.',
                languageLabel: 'Python',
                relatedFiles: const <String>['leetcode/two_sum.py'],
                acceptanceCriteria: const <String>[
                  'Use a lookup dictionary while iterating.',
                  'Check whether the complement already exists.',
                  'Return the pair of indices.',
                ],
                taskSteps: const <TaskStep>[
                  TaskStep(
                    id: 'io',
                    title: 'Identify input and output',
                    description:
                        'You receive a list of numbers and a target, and you need two indices back.',
                  ),
                  TaskStep(
                    id: 'lookup',
                    title: 'Choose the right structure',
                    description:
                        'A hash map gives you O(1) average lookups for complements.',
                  ),
                  TaskStep(
                    id: 'scan',
                    title: 'Scan once',
                    description:
                        'Check the complement first, then save the current value.',
                  ),
                ],
                supportedModes: const <PracticeMode>[
                  PracticeMode.guided,
                  PracticeMode.standard,
                  PracticeMode.timed,
                ],
                hints: const <HintLevel, String>{
                  HintLevel.concept: 'This is a complement lookup pattern.',
                  HintLevel.structure:
                      'Loop through `nums` with index and value. Track seen values in a dict.',
                  HintLevel.pseudocode:
                      'For each number, compute `target - num`. If it is in the map, return the stored index and current index. Otherwise store the current number.',
                  HintLevel.lineHint:
                      'A common shape is `if complement in seen: return [seen[complement], index]`.',
                  HintLevel.fullExplain:
                      'This milestone tests whether you can move from pattern recognition to a one-pass implementation.',
                },
                starterCode: '''def two_sum(nums, target):
    seen = {}
    return []
''',
                exampleInput: 'nums = [2, 7, 11, 15], target = 9',
                exampleOutput: '[0, 1]',
                testCases: const <ExecutionTestCase>[
                  ExecutionTestCase(
                    id: 'two_sum_primary',
                    label: 'Finds the first sample pair',
                    body: '''
print(two_sum([2, 7, 11, 15], 9))
''',
                    expectedOutput: '[0, 1]',
                  ),
                  ExecutionTestCase(
                    id: 'two_sum_middle_pair',
                    label: 'Handles a pair in the middle of the array',
                    body: '''
print(two_sum([3, 2, 4], 6))
''',
                    expectedOutput: '[1, 2]',
                  ),
                  ExecutionTestCase(
                    id: 'two_sum_duplicate_values',
                    label: 'Handles duplicate values without reusing one index',
                    body: '''
print(two_sum([3, 3], 6))
''',
                    expectedOutput: '[0, 1]',
                  ),
                ],
                reflectionPrompts: const <String>[
                  'Why does storing values after the lookup avoid using the same element twice?',
                  'What is the time and space complexity of this solution?',
                ],
                skillIds: const <String>[
                  'python_dict_usage',
                  'hashmap_counting',
                  'two_pointers_pattern',
                ],
                requirements: const <RequirementCheck>[
                  RequirementCheck(
                    label: 'Function exists',
                    pattern: r'def\s+two_sum\s*\(',
                    feedback: 'Define the `two_sum` function.',
                  ),
                  RequirementCheck(
                    label: 'Lookup map initialized',
                    pattern: r'seen\s*=\s*\{',
                    feedback:
                        'Initialize a dictionary to remember seen values.',
                  ),
                  RequirementCheck(
                    label: 'Complement computed',
                    pattern: r'complement\s*=\s*target\s*-\s*\w+',
                    feedback: 'Compute the complement for the current value.',
                  ),
                  RequirementCheck(
                    label: 'Checks existing complement',
                    pattern: r'if\s+complement\s+in\s+seen',
                    feedback:
                        'Check whether the complement is already in the map.',
                  ),
                  RequirementCheck(
                    label: 'Stores current index',
                    pattern: r'seen\[\w+\]\s*=\s*\w+',
                    feedback:
                        'Store the current value and index after checking.',
                  ),
                ],
                reviewPrompt:
                    'Reinforce the one-pass hash map pattern with a classic interview warmup.',
              ),
            ],
          ),
        ],
      ),
      LearningTrack(
        id: 'leetcode_sliding_window',
        title: 'LeetCode: Sliding Window',
        summary:
            'Build up window movement intuition and strengthen edge-case thinking.',
        type: LearningTrackType.leetcode,
        difficultyLabel: 'Medium prep',
        focusAreas: const <String>[
          'Python',
          'Sliding window',
          'Substring',
          'Edge cases'
        ],
        modules: <LearningModule>[
          LearningModule(
            id: 'longest_unique_substring',
            title: 'Longest substring without repeats',
            summary: 'Stretch into a mobile-friendly guided interview flow.',
            estimatedMinutes: 18,
            milestones: <Milestone>[
              Milestone(
                id: 'ms_longest_substring',
                title: 'Longest substring without repeating characters',
                objective: 'Track a shrinking window with last-seen indices.',
                problemStatement:
                    'Implement `length_of_longest_substring(s)` to return the length of the longest substring without repeated characters.',
                languageLabel: 'Python',
                relatedFiles: const <String>['leetcode/longest_substring.py'],
                acceptanceCriteria: const <String>[
                  'Track the left edge of the window.',
                  'Remember the last index of each character.',
                  'Update the max length as the window moves.',
                ],
                taskSteps: const <TaskStep>[
                  TaskStep(
                    id: 'window_state',
                    title: 'Track the window state',
                    description:
                        'Maintain the left boundary and the best length so far.',
                  ),
                  TaskStep(
                    id: 'last_seen',
                    title: 'Remember character positions',
                    description:
                        'Store the last index for each character in a dictionary.',
                  ),
                  TaskStep(
                    id: 'max_update',
                    title: 'Refresh the answer',
                    description:
                        'After adjusting the window, compute the current length and update the best result.',
                  ),
                ],
                supportedModes: const <PracticeMode>[
                  PracticeMode.guided,
                  PracticeMode.standard,
                  PracticeMode.timed,
                ],
                hints: const <HintLevel, String>{
                  HintLevel.concept:
                      'A sliding window expands to the right and only shrinks when a rule is violated.',
                  HintLevel.structure:
                      'Keep `left`, `best`, and a dictionary of last seen indices.',
                  HintLevel.pseudocode:
                      'When a repeated character is inside the active window, move `left` to one past its last index.',
                  HintLevel.lineHint:
                      'Look for a line like `left = max(left, last_seen[ch] + 1)`.',
                  HintLevel.fullExplain:
                      'This is a classic example of mixing a dynamic window with a hash map for O(n) time.',
                },
                starterCode: '''def length_of_longest_substring(s):
    left = 0
    best = 0
    last_seen = {}
    return best
''',
                exampleInput: 'abcabcbb',
                exampleOutput: '3',
                testCases: const <ExecutionTestCase>[
                  ExecutionTestCase(
                    id: 'longest_substring_primary',
                    label: 'Matches the canonical repeated-pattern sample',
                    body: '''
print(length_of_longest_substring("abcabcbb"))
''',
                    expectedOutput: '3',
                  ),
                  ExecutionTestCase(
                    id: 'longest_substring_all_same',
                    label: 'Shrinks correctly when every char repeats',
                    body: '''
print(length_of_longest_substring("bbbbb"))
''',
                    expectedOutput: '1',
                  ),
                  ExecutionTestCase(
                    id: 'longest_substring_overlap',
                    label: 'Moves left boundary only forward on overlap',
                    body: '''
print(length_of_longest_substring("pwwkew"))
''',
                    expectedOutput: '3',
                  ),
                ],
                reflectionPrompts: const <String>[
                  'Why do we use `max(left, last_seen[ch] + 1)` instead of assigning blindly?',
                  'How does this differ from a counting-based sliding window?',
                ],
                skillIds: const <String>[
                  'python_dict_usage',
                  'sliding_window',
                  'testing_edge_cases',
                ],
                requirements: const <RequirementCheck>[
                  RequirementCheck(
                    label: 'Function exists',
                    pattern: r'def\s+length_of_longest_substring\s*\(',
                    feedback: 'Define the target function.',
                  ),
                  RequirementCheck(
                    label: 'Tracks left pointer',
                    pattern: r'left\s*=',
                    feedback: 'Maintain a left pointer for the active window.',
                  ),
                  RequirementCheck(
                    label: 'Uses last_seen map',
                    pattern: r'last_seen\s*=\s*\{',
                    feedback:
                        'Use a dictionary to remember the last index of each character.',
                  ),
                  RequirementCheck(
                    label: 'Adjusts left on repeat',
                    pattern: r'left\s*=\s*max\(',
                    feedback:
                        'Move the left edge only forward when you see a repeat.',
                  ),
                  RequirementCheck(
                    label: 'Updates best length',
                    pattern: r'best\s*=\s*max\(',
                    feedback: 'Track the best window length seen so far.',
                  ),
                ],
                reviewPrompt:
                    'Review window movement and last-seen lookups with one focused drill.',
              ),
            ],
          ),
        ],
      ),
    ];
  }

  static List<SkillNode> skills() {
    return const <SkillNode>[
      SkillNode(
        id: 'python_class_definition',
        title: 'Python class definition',
        category: SkillCategory.languageSyntax,
        description:
            'Define classes, constructors, and instance methods in Python.',
        reviewMilestoneId: 'ms_python_document_class',
      ),
      SkillNode(
        id: 'python_instance_fields',
        title: 'Python instance fields',
        category: SkillCategory.oopClassDesign,
        description:
            'Store incoming values on self and use them in later behavior.',
        reviewMilestoneId: 'ms_python_document_class',
      ),
      SkillNode(
        id: 'python_dict_usage',
        title: 'Python dictionary usage',
        category: SkillCategory.languageSyntax,
        description:
            'Use dictionaries for lookups, counters, and last-seen patterns.',
        reviewMilestoneId: 'ms_frequency_counter',
      ),
      SkillNode(
        id: 'csharp_properties',
        title: 'C# properties',
        category: SkillCategory.languageSyntax,
        description: 'Define simple auto-properties for domain entities.',
        reviewMilestoneId: 'ms_csharp_todo_item',
      ),
      SkillNode(
        id: 'csharp_methods',
        title: 'C# methods',
        category: SkillCategory.oopClassDesign,
        description: 'Encapsulate state changes behind small behavior methods.',
        reviewMilestoneId: 'ms_csharp_todo_item',
      ),
      SkillNode(
        id: 'linked_list_basics',
        title: 'Linked list basics',
        category: SkillCategory.dataStructureFundamentals,
        description: 'Model nodes and update next pointers safely.',
        reviewMilestoneId: 'ms_linked_list_node',
      ),
      SkillNode(
        id: 'hashmap_counting',
        title: 'Hash map counting',
        category: SkillCategory.dataStructureFundamentals,
        description:
            'Use dictionary counts to solve repetition and lookup tasks.',
        reviewMilestoneId: 'ms_frequency_counter',
      ),
      SkillNode(
        id: 'two_pointers_pattern',
        title: 'Pair lookup pattern',
        category: SkillCategory.algorithmPatterns,
        description:
            'Translate interview prompts into efficient pair-search logic.',
        reviewMilestoneId: 'ms_two_sum_guided',
      ),
      SkillNode(
        id: 'sliding_window',
        title: 'Sliding window',
        category: SkillCategory.algorithmPatterns,
        description:
            'Track moving subarrays or substrings with dynamic boundaries.',
        reviewMilestoneId: 'ms_longest_substring',
      ),
      SkillNode(
        id: 'testing_edge_cases',
        title: 'Testing edge cases',
        category: SkillCategory.testingEdgeCases,
        description:
            'Check empty input, duplicates, and boundary behavior before shipping.',
        reviewMilestoneId: 'ms_longest_substring',
      ),
    ];
  }

  static Map<String, SkillMasteryRecord> skillMemory() {
    return <String, SkillMasteryRecord>{
      for (final skill in skills())
        skill.id: SkillMasteryRecord(
          skillId: skill.id,
          masteryScore: switch (skill.id) {
            'python_class_definition' => 0.58,
            'python_instance_fields' => 0.52,
            'python_dict_usage' => 0.64,
            'csharp_properties' => 0.41,
            'csharp_methods' => 0.47,
            'linked_list_basics' => 0.45,
            'hashmap_counting' => 0.67,
            'two_pointers_pattern' => 0.51,
            'sliding_window' => 0.36,
            'testing_edge_cases' => 0.49,
            _ => 0.5,
          },
          confidenceScore: 0.55,
          hintDependence: 0.32,
          failureCount: skill.id == 'sliding_window' ? 3 : 1,
          lastOutcome: skill.id == 'sliding_window'
              ? 'Needed pseudocode hint yesterday'
              : 'Practiced this week',
        ),
    };
  }
}
