'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {HttpsError} = require('firebase-functions/v2/https');
const {
  amountInGrams,
  comparePhoto,
  decodeImage,
  estimateMissingNutrition,
  findUsdaNutrition,
  generateJson,
  identifyMeal,
  isNutrition,
  parseJsonObject,
  selectUsdaFood,
  toJsonSchema,
  validateIngredients,
} = require('./index')._test;

const withEnv = async (key, value, action) => {
  const previous = process.env[key];
  process.env[key] = value;
  try {
    return await action();
  } finally {
    if (previous === undefined) delete process.env[key];
    else process.env[key] = previous;
  }
};

const withFetch = async (mock, action) => {
  const previous = global.fetch;
  global.fetch = mock;
  try {
    return await action();
  } finally {
    global.fetch = previous;
  }
};

test('ingredient amounts convert grams, millilitres, and common pieces', () => {
  assert.equal(amountInGrams({name: 'Egg', amount: 2, unit: 'pcs'}), 100);
  assert.equal(amountInGrams({name: 'Banana', amount: 1, unit: 'pcs'}), 118);
  assert.equal(amountInGrams({name: 'Rice', amount: 150, unit: 'g'}), 150);
  assert.equal(amountInGrams({name: 'Milk', amount: 100, unit: 'ml'}), 100);
});

test('ingredient validation rejects invalid quantities and units', () => {
  assert.deepEqual(validateIngredients([
    {name: 'Egg', amount: 2, unit: 'pcs'},
  ]), [{name: 'Egg', amount: 2, unit: 'pcs'}]);
  assert.throws(
    () => validateIngredients([{name: 'Egg', amount: 0, unit: 'pcs'}]),
    HttpsError,
  );
  assert.throws(
    () => validateIngredients([{name: 'Egg', amount: 2, unit: 'cup'}]),
    HttpsError,
  );
});

test('image input is validated and nutrition values are checked', () => {
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
  assert.deepEqual(
    decodeImage(jpeg.toString('base64'), 'image/jpeg'),
    {bytes: jpeg, mimeType: 'image/jpeg'},
  );
  assert.equal(
    decodeImage(jpeg.toString('base64'), null).mimeType,
    'image/jpeg',
  );
  assert.throws(() => decodeImage('not base64!'), HttpsError);
  assert.throws(
    () =>
      decodeImage(
        `data:image/jpeg;base64,${jpeg.toString('base64')}`,
        'image/jpeg',
      ),
    HttpsError,
  );
  assert.throws(
    () => decodeImage(jpeg.toString('base64'), 'image/png'),
    HttpsError,
  );
  assert.equal(
    isNutrition({calories: 100, protein: 2, carbs: 10, fat: 4}),
    true,
  );
  assert.equal(
    isNutrition({calories: -1, protein: 2, carbs: 10, fat: 4}),
    false,
  );
});

test('Groq requests use the current model, bearer auth, JSON mode, and OpenAI image parts', async () => {
  let capturedUrl;
  let capturedRequest;
  await withEnv('GROQ_API_KEY', 'unit-test-key', () =>
    withFetch(
      async (input, options) => {
        capturedUrl = new URL(input);
        capturedRequest = options;
        return new Response(
          JSON.stringify({
            choices: [{
              message: {content: '{"is_food":true}'},
              finish_reason: 'stop',
            }],
          }),
          {status: 200},
        );
      },
      async () => {
        const result = await generateJson(
          [
            {
              inline_data: {
                mime_type: 'image/jpeg',
                data: 'aGVsbG8=',
              },
            },
          ],
          {type: 'OBJECT'},
        );
        assert.deepEqual(result, {is_food: true});
        assert.equal(
          capturedUrl.href,
          'https://api.groq.com/openai/v1/chat/completions',
        );
        assert.equal(capturedRequest.headers.Authorization, 'Bearer unit-test-key');
        const request = JSON.parse(capturedRequest.body);
        assert.equal(request.model, 'qwen/qwen3.8-27b');
        assert.deepEqual(request.response_format, {type: 'json_object'});
        assert.equal(request.temperature, 0.1);
        assert.equal(request.max_tokens, 1024);
        assert.equal(request.messages[0].content[0].type, 'text');
        assert.match(request.messages[0].content[0].text, /"type":"object"/);
        assert.deepEqual(request.messages[0].content[1], {
          type: 'image_url',
          image_url: {url: 'data:image/jpeg;base64,aGVsbG8='},
        });
      },
    ),
  );
});

test('meal scans return detected meal details and identify non-food images', async () => {
  const responses = [
    {
      is_food: true,
      meal_name: 'Eggs and toast',
      meal_type: 'Breakfast',
      ingredients: [
        {name: 'Egg', amount: 2, unit: 'pcs'},
        {name: 'Whole wheat toast', amount: 60, unit: 'g'},
      ],
    },
    {
      is_food: false,
      meal_name: '',
      meal_type: 'Lunch',
      ingredients: [],
    },
  ];
  await withEnv('GROQ_API_KEY', 'unit-test-key', () =>
    withFetch(
      async () =>
        new Response(
          JSON.stringify({
            choices: [{
              message: {content: JSON.stringify(responses.shift())},
              finish_reason: 'stop',
            }],
          }),
          {status: 200},
        ),
      async () => {
        const image = Buffer.from('fake jpeg');
        const meal = await identifyMeal(image, 'image/jpeg');
        assert.deepEqual(meal, {
          is_food: true,
          meal_name: 'Eggs and toast',
          meal_type: 'Breakfast',
          ingredients: [
            {name: 'Egg', amount: 2, unit: 'pcs'},
            {name: 'Whole wheat toast', amount: 60, unit: 'g'},
          ],
        });
        const notFood = await identifyMeal(image, 'image/jpeg');
        assert.equal(notFood.is_food, false);
        assert.deepEqual(notFood.ingredients, []);
      },
    ),
  );
});

test('Groq estimates missing ingredient nutrition and compares photos', async () => {
  const responses = [
    {items: [{calories: 100, protein: 3, carbs: 20, fat: 1}]},
    {matches: false},
  ];
  await withEnv('GROQ_API_KEY', 'unit-test-key', () =>
    withFetch(
      async () =>
        new Response(
          JSON.stringify({
            choices: [{message: {content: JSON.stringify(responses.shift())}}],
          }),
          {status: 200},
        ),
      async () => {
        const ingredients = [{name: 'Cooked lentils'}];
        assert.deepEqual(
          await estimateMissingNutrition(ingredients),
          new Map([
            ['Cooked lentils', {calories: 100, protein: 3, carbs: 20, fat: 1}],
          ]),
        );
        assert.equal(
          await comparePhoto(
            Buffer.from('fake jpeg'),
            'image/jpeg',
            [{name: 'Rice', amount: 100, unit: 'g'}],
          ),
          false,
        );
      },
    ),
  );
});

test('Groq errors preserve provider status and exact response body', async () => {
  const errors = [];
  const originalError = console.error;
  console.error = (...args) => errors.push(args);
  try {
    await withEnv('GROQ_API_KEY', 'unit-test-key', () =>
      withFetch(
        async () =>
          new Response('{"error":{"message":"invalid test key"}}', {
            status: 401,
          }),
        async () => {
          await assert.rejects(
            generateJson([{text: 'hello'}], {type: 'OBJECT'}),
            (error) => {
              assert.equal(error.code, 'unavailable');
              assert.deepEqual(error.details, {
                provider: 'Groq',
                httpStatus: 401,
                responseBody: '{"error":{"message":"invalid test key"}}',
              });
              return true;
            },
          );
        },
      ),
    );
    assert.equal(errors.length, 1);
    assert.deepEqual(errors[0][1], {
      provider: 'Groq',
      httpStatus: 401,
      responseBody: '{"error":{"message":"invalid test key"}}',
    });
  } finally {
    console.error = originalError;
  }
});

test('Groq retries rate limits with backoff and eventually succeeds', async () => {
  let calls = 0;
  await withEnv('GROQ_API_KEY', 'unit-test-key', () =>
    withFetch(
      async () => {
        calls++;
        if (calls === 1) return new Response('busy', {status: 429});
        return new Response(
          JSON.stringify({
            choices: [{message: {content: '{"ok":true}'}}],
          }),
          {status: 200},
        );
      },
      async () => {
        const result = await generateJson([{text: 'hello'}], {type: 'OBJECT'});
        assert.deepEqual(result, {ok: true});
        assert.equal(calls, 2);
      },
    ),
  );
});

test('Groq stops after four rate-limited attempts with a retryable callable error', async () => {
  let calls = 0;
  await withEnv('GROQ_API_KEY', 'unit-test-key', () =>
    withFetch(
      async () => {
        calls++;
        return new Response('busy', {status: 429});
      },
      async () => {
        await assert.rejects(
          generateJson([{text: 'hello'}], {type: 'OBJECT'}),
          (error) => {
            assert.equal(error.code, 'resource-exhausted');
            assert.equal(error.details.httpStatus, 429);
            return true;
          },
        );
        assert.equal(calls, 4);
      },
    ),
  );
});

test('Groq retries without JSON response format when it rejects image JSON mode', async () => {
  let calls = 0;
  await withEnv('GROQ_API_KEY', 'unit-test-key', () =>
    withFetch(
      async (_input, options) => {
        calls++;
        const request = JSON.parse(options.body);
        if (calls === 1) {
          assert.ok(request.response_format);
          return new Response('response_format is not supported with image input', {
            status: 400,
          });
        }
        assert.equal(request.response_format, undefined);
        return new Response(
          JSON.stringify({choices: [{message: {content: '{"ok":true}'}}]}),
          {status: 200},
        );
      },
      async () => {
        const result = await generateJson(
          [{inline_data: {mime_type: 'image/jpeg', data: 'aGVsbG8='}}],
          {type: 'OBJECT'},
        );
        assert.deepEqual(result, {ok: true});
        assert.equal(calls, 2);
      },
    ),
  );
});

test('Groq response parser accepts surrounding text and converts nested schema types', () => {
  assert.deepEqual(parseJsonObject('Here is the result: {"ok":true} thanks'), {
    ok: true,
  });
  assert.deepEqual(
    toJsonSchema({
      type: 'OBJECT',
      properties: {
        values: {type: 'ARRAY', items: {type: 'NUMBER'}},
        valid: {type: 'BOOLEAN'},
      },
      required: ['values', 'valid'],
    }),
    {
      type: 'object',
      properties: {
        values: {type: 'array', items: {type: 'number'}},
        valid: {type: 'boolean'},
      },
      required: ['values', 'valid'],
    },
  );
});

test('USDA uses the required search filters and falls back to Atwater energy', async () => {
  await withEnv('USDA_API_KEY', 'unit-test-usda-key', () =>
    withFetch(
      async (input) => {
        const url = new URL(input);
        assert.equal(url.searchParams.get('dataType'), 'Foundation,SR Legacy');
        assert.equal(url.searchParams.get('pageSize'), '5');
        assert.equal(url.searchParams.get('api_key'), 'unit-test-usda-key');
        return new Response(
          JSON.stringify({
            foods: [
              {
                description: 'Egg, whole, raw, fresh',
                foodNutrients: [{nutrientId: 1008, value: 143}],
              },
              {
                description: 'Egg, whole, cooked',
                foodNutrients: [
                  {nutrientId: 1008, value: 0},
                  {nutrientId: 2047, value: 155},
                  {nutrientId: 1003, value: 13},
                  {nutrientId: 1005, value: 1.1},
                  {nutrientId: 1004, value: 11},
                ],
              },
            ],
          }),
          {status: 200},
        );
      },
      async () => {
        assert.deepEqual(await findUsdaNutrition('egg whole cooked'), {
          calories: 155,
          protein: 13,
          carbs: 1.1,
          fat: 11,
        });

        test('USDA search prefers the description most similar to the ingredient', () => {
          const foods = [
            {description: 'Rice, white, cooked', foodNutrients: []},
            {description: 'Rice, brown, raw', foodNutrients: []},
            {description: 'Tomatoes, red, ripe, raw', foodNutrients: []},
          ];
          assert.equal(selectUsdaFood(foods, 'cooked white rice'), foods[0]);
        });
      },
    ),
  );
});

test('USDA errors preserve provider status and exact response body', async () => {
  const errors = [];
  const originalError = console.error;
  console.error = (...args) => errors.push(args);
  try {
    await withEnv('USDA_API_KEY', 'unit-test-usda-key', () =>
      withFetch(
        async () => new Response('{"error":"quota"}', {status: 403}),
        async () => {
          await assert.rejects(
            findUsdaNutrition('egg'),
            (error) => {
              assert.equal(error.code, 'unavailable');
              assert.deepEqual(error.details, {
                provider: 'USDA FoodData Central',
                httpStatus: 403,
                responseBody: '{"error":"quota"}',
              });
              return true;
            },
          );
        },
      ),
    );
    assert.equal(errors.length, 1);
    assert.deepEqual(errors[0][1], {
      provider: 'USDA FoodData Central',
      httpStatus: 403,
      responseBody: '{"error":"quota"}',
    });
  } finally {
    console.error = originalError;
  }
});
