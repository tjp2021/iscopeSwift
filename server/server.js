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
        const { fileName } = req.body;
        
        const params = {
            Bucket: 'iscope',
            Key: `videos/${Date.now()}-${fileName}`,
            Expires: 300,
            ContentType: 'video/mp4'
        };

        const uploadURL = await s3.getSignedUrlPromise('putObject', params);
        
        res.json({
            uploadURL,
            videoKey: params.Key
        });
    } catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: error.message });
    }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
}); 