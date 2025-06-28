import json
import boto3
import uuid

s3 = boto3.client('s3')
translate = boto3.client('translate')

def handler(event, context):
    body = json.loads(event['body'])
    text = body['text']
    target_language = body['target_language']
    
    # Translate text
    response = translate.translate_text(
        Text=text,
        SourceLanguageCode='auto',
        TargetLanguageCode=target_language
    )
    translated_text = response['TranslatedText']
    
    # Generate unique key
    key = str(uuid.uuid4())
    
    # Store input in request-bucket
    input_data = {'text': text, 'target_language': target_language}
    s3.put_object(
        Bucket='request-bucket-capstone',
        Key=f'{key}_input.json',
        Body=json.dumps(input_data)
    )
    
    # Store output in response-bucket
    output_data = {'original_text': text, 'translated_text': translated_text, 'target_language': target_language}
    s3.put_object(
        Bucket='response-bucket-capstone',
        Key=f'{key}_output.json',
        Body=json.dumps(output_data)
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({'translated_text': translated_text})
    }