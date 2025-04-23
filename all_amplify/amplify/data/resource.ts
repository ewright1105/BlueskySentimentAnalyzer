import { type ClientSchema, a, defineData } from '@aws-amplify/backend';

const schema = a.schema({
  Topic: a
    .model({
      topic:a.string(),
      intervalLength: a.integer(), 
      intervalUnit: a.string(),
      numberOfIntervals: a.integer(), 
      time: a.integer(),
    })
    .authorization((allow) => [allow.owner()]),

});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: 'userPool',
  },
});