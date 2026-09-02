#!/usr/bin/env node
import { stdin, stdout } from 'node:process';
import { createInterface } from 'node:readline/promises';
import { hashPassword } from '../src/password.js';

const argument = process.argv[2];
let password = argument;
if (!password) {
  if (!stdin.isTTY) {
    password = (await new Promise((resolve) => {
      let value = '';
      stdin.setEncoding('utf8');
      stdin.on('data', (chunk) => { value += chunk; });
      stdin.on('end', () => resolve(value.trimEnd()));
    }));
  } else {
    const reader = createInterface({ input: stdin, output: stdout });
    password = await reader.question('Password (input is visible): ');
    reader.close();
  }
}

try {
  stdout.write(`${await hashPassword(password)}\n`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
