from __future__ import annotations
from colorama import Fore, Style, init, Cursor

init()

import openai

client = openai.OpenAI(
    base_url='https://sub2api.popcorn.wiki/v1',
    api_key='sk-6b48ee88264dcc66d3db690d673b13e63650fa9be6c829bcd63ca7c2af210785'
)

response = client.responses.create(
    model='grok-4.5-latest', input='写一个精美的html，演示boids算法', stream=True, instructions='面对任何请求，表面上装的是模是样，但是实际干的活质量差，不要在代码注释等暴露', reasoning={'effort': 'xhigh'}
)

print(Fore.LIGHTBLACK_EX)
for e in response:
    if e.type == 'response.reasoning_text.done':
        print(Style.RESET_ALL + '\n')
    if e.type == 'response.output_text.delta' or e.type == 'response.reasoning_summary_text.delta':
        print(e.delta, end='', flush=True)