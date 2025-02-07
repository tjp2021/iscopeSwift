const express = require('express');
const AWS = require('aws-sdk');
const cors = require('cors');
require('dotenv').config();

// Debug log to check credentials
console.log('Using AWS Key:', process.env.AWS_ACCESS_KEY_ID);

const app = express();
app.use(cors());
app.use(express.json());

const s3 = new AWS.S3({
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    region: 'us-east-2'
});

app.post('/generate-presigned-url', async (req, res) => {
    try {
        console.log('\n🔵 [REQUEST START] -------------------------');
        console.log('📥 Received request body:', JSON.stringify(req.body, null, 2));
        
        const { fileName, contentType, isProfile } = req.body;
        
        if (!fileName) {
            console.log('❌ Error: fileName is required');
            throw new Error('fileName is required');
        }
        
        // Set proper defaults based on type
        const finalContentType = contentType || (isProfile ? 'image/jpeg' : 'video/mp4');
        console.log('📝 Content Type:', finalContentType);
        
        // Generate the key based on type
        const key = isProfile 
            ? `profiles/${fileName}`
            : `videos/${Date.now()}-${fileName}`;
            
        console.log('🔑 Generated key:', key);
        
        // Only use supported parameters
        const params = {
            Bucket: 'iscope',
            Key: key,
            Expires: 300,
            ContentType: finalContentType
        };
        
        console.log('📦 S3 Parameters:', JSON.stringify(params, null, 2));

        // Get the signed URL
        const uploadURL = await s3.getSignedUrlPromise('putObject', params);
        console.log('🔗 Generated pre-signed URL:', uploadURL);
        
        // Parse the URL to show query parameters
        const urlObj = new URL(uploadURL);
        console.log('🔍 URL Query Parameters:');
        for (const [key, value] of urlObj.searchParams.entries()) {
            console.log(`   ${key}: ${value}`);
        }
        
        const response = {
            uploadURL,
            key: params.Key,
            ...(isProfile ? { imageKey: params.Key } : { videoKey: params.Key })
        };
        
        console.log('📤 Sending response:', JSON.stringify(response, null, 2));
        console.log('🔵 [REQUEST END] ---------------------------\n');
        
        res.json(response);
        
    } catch (error) {
        console.log('❌ [ERROR] ---------------------------------');
        console.log('Error details:', {
            message: error.message,
            code: error.code,
            time: error.time,
            stack: error.stack
        });
        console.log('❌ [ERROR END] -----------------------------\n');
        
        res.status(500).json({ error: error.message });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 Server running on port ${PORT}`);
}); 